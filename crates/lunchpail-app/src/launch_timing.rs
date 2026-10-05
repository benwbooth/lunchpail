//! Local, bounded launch diagnostics. Producers never wait for disk IO.
//! Only explicitly selected metadata belongs here: no credentials or commands.
use fs2::FileExt;
use serde_json::{Value, json};
use std::{
    fs::OpenOptions,
    io::{self, Write},
    path::Path,
    sync::{Arc, Mutex, OnceLock, mpsc},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

const MAX_LOG_BYTES: u64 = 5 * 1024 * 1024;
const LOG_NAME: &str = "launch-timing.jsonl";
static WRITER: OnceLock<Option<mpsc::SyncSender<Value>>> = OnceLock::new();
// Lunchpail admits one launch at a time. Retain the request through the
// pre-launch save check, then transfer it to the emulator worker. Sync workers
// clone the trace before starting, so retries and UI delivery keep the same ID.
static PENDING: Mutex<Option<Timing>> = Mutex::new(None);

#[derive(Clone)]
pub(crate) struct Timing(Arc<Trace>);

struct Trace {
    id: String,
    kind: &'static str,
    game_id: String,
    title: String,
    started: Instant,
    previous: Mutex<Instant>,
    sender: Option<mpsc::SyncSender<Value>>,
}

impl Timing {
    pub(crate) fn new(kind: &'static str, game_id: &str, title: &str) -> Self {
        Self::with_sender(kind, game_id, title, writer().cloned())
    }

    fn with_sender(
        kind: &'static str,
        game_id: &str,
        title: &str,
        sender: Option<mpsc::SyncSender<Value>>,
    ) -> Self {
        let now = Instant::now();
        Self(Arc::new(Trace {
            id: uuid::Uuid::new_v4().to_string(),
            kind,
            game_id: game_id.to_owned(),
            title: title.to_owned(),
            started: now,
            previous: Mutex::new(now),
            sender,
        }))
    }

    pub(crate) fn event(&self, stage: &str, details: Value) {
        let Some(sender) = &self.0.sender else { return };
        let Ok(mut previous) = self.0.previous.lock() else {
            return;
        };
        let now = Instant::now();
        let record = json!({
            "schema": 1,
            "timestamp_ms": SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis(),
            "pid": std::process::id(),
            "version": env!("CARGO_PKG_VERSION"),
            "build_hash": env!("LUNCHPAIL_BUILD_HASH"),
            "built_unix": env!("LUNCHPAIL_BUILT_UNIX"),
            "debug_build": cfg!(debug_assertions),
            "trace_id": self.0.id,
            "kind": self.0.kind,
            "game_id": self.0.game_id,
            "title": self.0.title,
            "stage": stage,
            "elapsed_ms": now.duration_since(self.0.started).as_secs_f64() * 1000.0,
            "delta_ms": now.duration_since(*previous).as_secs_f64() * 1000.0,
            "details": details,
        });
        *previous = now;
        if sender.try_send(record).is_err() {
            warn_once("launch timing queue is full or unavailable; some events were dropped");
        }
    }
}

pub(crate) fn begin_launch(game_id: &str, title: &str) {
    let timing = Timing::new("launch", game_id, title);
    timing.event("launch_requested", json!({}));
    if let Ok(mut pending) = PENDING.lock() {
        *pending = Some(timing);
    }
}

pub(crate) fn pending_launch() -> Option<Timing> {
    PENDING.lock().ok()?.clone()
}

pub(crate) fn note_pending(stage: &str) {
    if let Some(timing) = pending_launch() {
        timing.event(stage, json!({}));
    }
}

pub(crate) fn take_launch(game_id: &str, title: &str) -> Timing {
    let pending = PENDING.lock().ok().and_then(|mut pending| pending.take());
    pending
        .filter(|timing| timing.0.game_id == game_id)
        .unwrap_or_else(|| {
            let timing = Timing::new("launch", game_id, title);
            timing.event("launch_requested", json!({"source": "direct"}));
            timing
        })
}

pub(crate) fn initialize() {
    Timing::new("application", "", "")
        .event("logging_ready", json!({"max_log_bytes": MAX_LOG_BYTES}));
}

fn warn_once(message: &str) {
    static WARNED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    if !WARNED.swap(true, std::sync::atomic::Ordering::Relaxed) {
        eprintln!("LUNCHPAIL_LAUNCH_TIMING_WARNING: {message}");
    }
}

fn writer() -> Option<&'static mpsc::SyncSender<Value>> {
    WRITER
        .get_or_init(|| {
            let directory = crate::app_paths::project_dirs()?
                .data_local_dir()
                .join("logs");
            let (send, receive) = mpsc::sync_channel(1024);
            match std::thread::Builder::new()
                .name("launch-timing-log".into())
                .spawn(move || {
                    for record in receive {
                        if let Err(error) = append_record(&directory, &record, MAX_LOG_BYTES) {
                            warn_once(&format!("could not write launch timings: {error}"));
                        }
                    }
                }) {
                Ok(_) => Some(send),
                Err(error) => {
                    warn_once(&format!("could not start launch timing writer: {error}"));
                    None
                }
            }
        })
        .as_ref()
}

fn private_append(path: &Path) -> io::Result<std::fs::File> {
    let mut options = OpenOptions::new();
    options.create(true).append(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}

fn append_record(directory: &Path, record: &Value, limit: u64) -> io::Result<()> {
    std::fs::create_dir_all(directory)?;
    // A detached game-session host may coexist with a new UI process. Lock
    // rotation and append together so both keep writing to the current file.
    let lock = private_append(&directory.join("launch-timing.lock"))?;
    lock.lock_exclusive()?;
    let path = directory.join(LOG_NAME);
    let mut bytes = serde_json::to_vec(record)?;
    bytes.push(b'\n');
    if path
        .metadata()
        .is_ok_and(|meta| meta.len() + bytes.len() as u64 > limit)
    {
        let previous = directory.join("launch-timing.previous.jsonl");
        match std::fs::remove_file(&previous) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
        std::fs::rename(&path, previous)?;
    }
    private_append(&path)?.write_all(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn save_sync_and_launch_worker_share_the_pending_request() {
        let (send, receive) = mpsc::sync_channel(4);
        let trace = Timing::with_sender("launch", "handoff-game", "Handoff", Some(send));
        *PENDING.lock().unwrap() = Some(trace);
        pending_launch()
            .unwrap()
            .event("save_sync_finished", json!({}));
        let worker = take_launch("handoff-game", "Handoff");
        assert!(pending_launch().is_none());
        worker.event("launch_worker_started", json!({}));
        assert_eq!(
            receive.recv().unwrap()["trace_id"],
            receive.recv().unwrap()["trace_id"]
        );
    }

    #[test]
    fn cloned_trace_preserves_identity_and_monotonic_stage_timings() {
        let (send, receive) = mpsc::sync_channel(4);
        let trace = Timing::with_sender("launch", "game-1", "Game\nTitle", Some(send));
        trace.event("launch_requested", json!({}));
        std::thread::spawn(move || {
            trace
                .clone()
                .event("save_sync_finished", json!({"actions": 0}))
        })
        .join()
        .unwrap();
        let first = receive.recv().unwrap();
        let second = receive.recv().unwrap();
        assert_eq!(first["trace_id"], second["trace_id"]);
        assert_eq!(second["title"], "Game\nTitle");
        let elapsed = second["elapsed_ms"].as_f64().unwrap();
        assert!(elapsed >= first["elapsed_ms"].as_f64().unwrap());
        assert!(
            (elapsed
                - first["elapsed_ms"].as_f64().unwrap()
                - second["delta_ms"].as_f64().unwrap())
            .abs()
                < 0.01
        );
    }

    #[test]
    fn saturated_or_disconnected_writer_does_not_block_launch() {
        let (send, receive) = mpsc::sync_channel(1);
        let trace = Timing::with_sender("launch", "", "", Some(send));
        trace.event("one", json!({}));
        trace.event("two", json!({}));
        drop(receive);
        trace.event("three", json!({}));
    }

    #[test]
    fn log_is_json_lines_and_rotates_to_one_previous_file() {
        let directory = tempfile::tempdir().unwrap();
        for stage in ["first", "second", "third"] {
            append_record(directory.path(), &json!({"stage": stage}), 25).unwrap();
        }
        let current = std::fs::read_to_string(directory.path().join(LOG_NAME)).unwrap();
        let previous =
            std::fs::read_to_string(directory.path().join("launch-timing.previous.jsonl")).unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&current).unwrap()["stage"],
            "third"
        );
        assert_eq!(
            serde_json::from_str::<Value>(&previous).unwrap()["stage"],
            "second"
        );
        assert!(current.ends_with('\n'));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                directory
                    .path()
                    .join(LOG_NAME)
                    .metadata()
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
    }

    #[test]
    fn concurrent_writers_keep_complete_records() {
        let directory = tempfile::tempdir().unwrap();
        std::thread::scope(|scope| {
            for worker in 0..4 {
                let directory = directory.path();
                scope.spawn(move || {
                    for sequence in 0..10 {
                        append_record(
                            directory,
                            &json!({"worker": worker, "sequence": sequence}),
                            MAX_LOG_BYTES,
                        )
                        .unwrap();
                    }
                });
            }
        });
        let content = std::fs::read_to_string(directory.path().join(LOG_NAME)).unwrap();
        assert_eq!(content.lines().count(), 40);
        assert!(
            content
                .lines()
                .all(|line| serde_json::from_str::<Value>(line).is_ok())
        );
    }
}
