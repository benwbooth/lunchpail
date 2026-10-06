use crate::{MAX_MESSAGE_BYTES, PROTOCOL_VERSION, Reply, Request};
use anyhow::{Context, Result, bail, ensure};
use std::{
    io::{BufRead, BufReader, Read, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Llm,
    Speech,
}

pub fn executable(directory: &Path, kind: Kind, gpu: bool) -> PathBuf {
    let name = match kind {
        Kind::Llm => "llm",
        Kind::Speech => "speech",
    };
    directory.join(format!(
        "lunchpail-{name}-{}{}",
        if gpu { "gpu" } else { "cpu" },
        std::env::consts::EXE_SUFFIX
    ))
}

/// Only bundled worker paths are used, never a program name from a model reply
/// or a system PATH lookup. CPU workers do not link a GPU runtime at all.
pub fn bundled_directory() -> Result<PathBuf> {
    if let Some(value) = std::env::var_os("LUNCHPAIL_INFERENCE_DIR") {
        return Ok(PathBuf::from(value));
    }
    let exe = std::env::current_exe()?;
    let parent = exe.parent().context("Finding bundled AI runtime")?;
    if executable(parent, Kind::Llm, false).is_file() {
        return Ok(parent.to_owned());
    }
    // `dev.sh` stages the same four packaged executables here.
    let development = parent.join("../inference");
    if executable(&development, Kind::Llm, false).is_file() {
        return Ok(development);
    }
    bail!("This build does not include the local AI workers. Install a complete Lunchpail package.")
}

pub struct Worker {
    child: Child,
    input: Option<ChildStdin>,
    replies: mpsc::Receiver<Result<Reply, String>>,
    diagnostics: Arc<Mutex<String>>,
}

impl Worker {
    pub fn start(path: &Path) -> Result<Self> {
        ensure!(
            path.is_file(),
            "Bundled inference runtime is missing: {}",
            path.display()
        );
        let mut command = Command::new(path);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000); // CREATE_NO_WINDOW
        }
        let mut child = command
            .spawn()
            .context("Starting bundled inference runtime")?;
        let input = child.stdin.take().context("Opening inference input")?;
        let output = child.stdout.take().context("Opening inference output")?;
        let errors = child
            .stderr
            .take()
            .context("Opening inference diagnostics")?;
        let (tx, replies) = mpsc::sync_channel(2);
        std::thread::spawn(move || {
            let mut reader = BufReader::new(output);
            loop {
                let mut bytes = Vec::new();
                match reader
                    .by_ref()
                    .take((MAX_MESSAGE_BYTES + 1) as u64)
                    .read_until(b'\n', &mut bytes)
                {
                    Ok(0) => break,
                    Ok(_) if bytes.len() <= MAX_MESSAGE_BYTES => {
                        let result = serde_json::from_slice(&bytes)
                            .map_err(|e| format!("Invalid inference reply: {e}"));
                        if tx.send(result).is_err() {
                            break;
                        }
                    }
                    Ok(_) => {
                        let _ = tx.send(Err("Inference reply exceeded its size limit".into()));
                        break;
                    }
                    Err(e) => {
                        let _ = tx.send(Err(e.to_string()));
                        break;
                    }
                }
            }
        });
        let diagnostics = Arc::new(Mutex::new(String::new()));
        let log = diagnostics.clone();
        std::thread::spawn(move || {
            let mut errors = errors;
            let mut buffer = [0_u8; 4096];
            while let Ok(count) = errors.read(&mut buffer) {
                if count == 0 {
                    break;
                }
                if let Ok(mut text) = log.lock() {
                    text.push_str(&String::from_utf8_lossy(&buffer[..count]));
                    if text.len() > 32_768 {
                        let mut split = text.len() - 24_576;
                        while !text.is_char_boundary(split) {
                            split += 1;
                        }
                        text.drain(..split);
                    }
                }
            }
        });
        Ok(Self {
            child,
            input: Some(input),
            replies,
            diagnostics,
        })
    }

    pub fn request(
        &mut self,
        request: &Request,
        cancel: &AtomicBool,
        timeout: Duration,
    ) -> Result<Reply> {
        ensure!(!cancel.load(Ordering::Relaxed), "Inference cancelled");
        let bytes = serde_json::to_vec(request)?;
        ensure!(
            bytes.len() < MAX_MESSAGE_BYTES,
            "Inference request exceeds its size limit"
        );
        let deadline = Instant::now() + timeout;
        let mut input = self
            .input
            .take()
            .context("Inference runtime input is closed")?;
        let (write_tx, write_rx) = mpsc::sync_channel(1);
        std::thread::spawn(move || {
            let result = input
                .write_all(&bytes)
                .and_then(|()| input.write_all(b"\n"))
                .and_then(|()| input.flush());
            let _ = write_tx.send((input, result));
        });
        // GPU initialization may stall before it starts reading stdin. Never
        // block cancellation on a pipe full of microphone samples.
        loop {
            if cancel.load(Ordering::Relaxed) || Instant::now() >= deadline {
                let _ = self.child.kill();
                bail!("Inference cancelled or timed out while sending the request");
            }
            match write_rx.recv_timeout(Duration::from_millis(20)) {
                Ok((input, result)) => {
                    self.input = Some(input);
                    result.context("Sending inference request")?;
                    break;
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    bail!("Inference input closed unexpectedly")
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
        }
        loop {
            if cancel.load(Ordering::Relaxed) || Instant::now() >= deadline {
                let _ = self.child.kill();
                bail!(if cancel.load(Ordering::Relaxed) {
                    "Inference cancelled"
                } else {
                    "Local inference timed out. Try a smaller model or GPU acceleration."
                });
            }
            match self.replies.recv_timeout(Duration::from_millis(40)) {
                Ok(result) => {
                    let reply = result.map_err(anyhow::Error::msg)?;
                    ensure!(
                        reply.version == PROTOCOL_VERSION,
                        "Bundled AI runtime version mismatch"
                    );
                    ensure!(reply.error.is_empty(), "{}", reply.error);
                    return Ok(reply);
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    let detail = self
                        .diagnostics
                        .lock()
                        .map(|s| s.clone())
                        .unwrap_or_default();
                    bail!(
                        "Local inference runtime exited unexpectedly. {}",
                        detail
                            .chars()
                            .rev()
                            .take(1800)
                            .collect::<String>()
                            .chars()
                            .rev()
                            .collect::<String>()
                    );
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
        }
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        // These are only our own disposable inference children, never Ollama
        // or any other user-owned process. Cancellation releases their VRAM.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub fn probe(directory: &Path, kind: Kind, cancel: &AtomicBool) -> Result<Reply> {
    let path = executable(directory, kind, true);
    let mut worker = Worker::start(&path)?;
    worker.request(&Request::Probe, cancel, Duration::from_secs(20))
}

/// Auto mode retries on a genuinely CPU-only executable if GPU startup/model
/// allocation fails. Explicit GPU mode reports the failure instead of lying
/// about acceleration. The same policy is used by both inference engines.
pub fn one_shot(
    directory: &Path,
    kind: Kind,
    mode: &str,
    request: &Request,
    cancel: &AtomicBool,
) -> Result<Reply> {
    Session::new(directory, kind, mode)?.request(request, cancel)
}

/// Keep model weights resident for a bounded multi-tool question; dropping
/// the session releases the child and its VRAM, including on cancellation.
pub struct Session {
    directory: PathBuf,
    kind: Kind,
    mode: String,
    gpu: bool,
    worker: Option<Worker>,
    warning: String,
}
impl Session {
    pub fn new(directory: &Path, kind: Kind, mode: &str) -> Result<Self> {
        ensure!(
            matches!(mode, "auto" | "cpu" | "gpu"),
            "Unknown compute preference"
        );
        Ok(Self {
            directory: directory.to_owned(),
            kind,
            mode: mode.into(),
            gpu: mode != "cpu",
            worker: None,
            warning: String::new(),
        })
    }
    pub fn request(&mut self, request: &Request, cancel: &AtomicBool) -> Result<Reply> {
        ensure!(!cancel.load(Ordering::Relaxed), "Inference cancelled");
        let result = (|| {
            if self.worker.is_none() {
                self.worker = Some(Worker::start(&executable(
                    &self.directory,
                    self.kind,
                    self.gpu,
                ))?);
            }
            self.worker
                .as_mut()
                .context("Inference runtime missing")?
                .request(request, cancel, Duration::from_secs(300))
        })();
        match result {
            Ok(mut reply) => {
                reply.warning = self.warning.clone();
                Ok(reply)
            }
            Err(error) if self.gpu && self.mode == "auto" && !cancel.load(Ordering::Relaxed) => {
                self.worker = None;
                self.gpu = false;
                self.warning = format!("GPU unavailable; using CPU. {error:#}");
                self.request(request, cancel)
            }
            Err(error) => {
                self.worker = None;
                Err(error)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn worker_names_never_come_from_model_output() {
        let path = executable(Path::new("bundle"), Kind::Llm, false);
        assert_eq!(path.file_stem().unwrap(), "lunchpail-llm-cpu");
        assert_eq!(
            executable(Path::new("bundle"), Kind::Speech, true)
                .file_stem()
                .unwrap(),
            "lunchpail-speech-gpu"
        );
    }
    #[test]
    fn invalid_compute_mode_is_rejected_before_starting_a_child() {
        assert!(
            one_shot(
                Path::new("unused"),
                Kind::Llm,
                "shell",
                &Request::Probe,
                &AtomicBool::new(false)
            )
            .is_err()
        );
    }
    #[test]
    #[cfg(unix)]
    fn auto_falls_back_but_explicit_gpu_does_not() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let cpu = executable(dir.path(), Kind::Llm, false);
        std::fs::write(&cpu, b"#!/bin/sh\nread request\nprintf '%s\\n' '{\"version\":1,\"text\":\"\",\"device\":\"CPU\",\"devices\":[],\"error\":\"\",\"warning\":\"\"}'\n").unwrap();
        std::fs::set_permissions(&cpu, std::fs::Permissions::from_mode(0o700)).unwrap();
        let cancel = AtomicBool::new(false);
        let reply = one_shot(dir.path(), Kind::Llm, "auto", &Request::Probe, &cancel).unwrap();
        assert_eq!(reply.device, "CPU");
        assert!(reply.warning.contains("GPU unavailable; using CPU"));
        assert!(one_shot(dir.path(), Kind::Llm, "gpu", &Request::Probe, &cancel).is_err());
        let cpu_only = one_shot(dir.path(), Kind::Llm, "cpu", &Request::Probe, &cancel).unwrap();
        assert!(cpu_only.warning.is_empty());
    }
    #[test]
    #[cfg(unix)]
    fn a_worker_that_never_reads_cannot_block_timeout() {
        use std::os::unix::fs::PermissionsExt;
        if !Path::new("/bin/sh").is_file() {
            return;
        }
        let dir = tempfile::tempdir().unwrap();
        let child = dir.path().join("stalled-worker");
        std::fs::write(&child, b"#!/bin/sh\nexec sleep 60\n").unwrap();
        std::fs::set_permissions(&child, std::fs::Permissions::from_mode(0o700)).unwrap();
        let mut worker = Worker::start(&child).unwrap();
        let request = Request::Generate {
            messages: Vec::new(),
            model: PathBuf::from("unused"),
            device: None,
            system: String::new(),
            prompt: "x".repeat(2 * 1024 * 1024),
            schema: serde_json::json!({}),
            max_tokens: 32,
        };
        let start = Instant::now();
        assert!(
            worker
                .request(
                    &request,
                    &AtomicBool::new(false),
                    Duration::from_millis(150)
                )
                .is_err()
        );
        assert!(start.elapsed() < Duration::from_secs(3));
    }
}
