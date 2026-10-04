//! Single-instance guard for the desktop application.
//!
//! Lunchpail owns one library, one settings store and one set of running
//! emulators, so a second GUI process must not start. The first process takes
//! an advisory lock on `instance.lock` in its per-user directory and listens
//! on a loopback socket; a later launch connects, asks the owner to raise its
//! window, and exits.
//!
//! `fs2` file locking and `std::net` are used instead of Qt's `QLocalServer`
//! so the guard works identically on Linux, macOS and Windows without another
//! C++ bridge. The socket is loopback-only and its port is published inside the
//! user's own data directory.

use anyhow::{Context, Result};
use directories::ProjectDirs;
use fs2::FileExt;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

/// Set by the listener thread and consumed by the Qt bridge on the GUI thread.
static RAISE_REQUESTED: AtomicBool = AtomicBool::new(false);
static RESTART_REQUESTED: AtomicBool = AtomicBool::new(false);
static RESTART_CONSUMED: AtomicBool = AtomicBool::new(false);

pub(crate) fn restarting() -> bool {
    RESTART_CONSUMED.load(Ordering::SeqCst)
}

/// Ask the exact visible process to relinquish its UI, not its launch worker.
/// Success means the instance lock was released, so the replacement may start.
pub(crate) fn prepare_dev_restart(pid: u32) -> Result<()> {
    let (lock_path, port_path) = paths()?;
    prepare_restart_at(&lock_path, &port_path, pid)
}

fn prepare_restart_at(lock_path: &Path, port_path: &Path, pid: u32) -> Result<()> {
    let port: u16 = std::fs::read_to_string(&port_path)?.trim().parse()?;
    let mut stream = TcpStream::connect_timeout(
        &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
        Duration::from_secs(2),
    )?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    writeln!(stream, "restart {pid}")?;
    let mut response = String::new();
    BufReader::new(stream).read_line(&mut response)?;
    anyhow::ensure!(
        response.trim() == "restarting",
        "the running UI does not support a safe restart handoff"
    );
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(lock_path)?;
    for _ in 0..100 {
        if lock.try_lock_exclusive().is_ok() {
            FileExt::unlock(&lock)?;
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    anyhow::bail!("the UI has not released its instance lock; leaving it and the game running")
}

/// Keeps the advisory lock and listener alive for the process lifetime.
pub(crate) struct InstanceGuard {
    _lock: std::fs::File,
    port_path: PathBuf,
}

impl Drop for InstanceGuard {
    fn drop(&mut self) {
        // Remove only the published port; the lock file itself stays so the
        // inode is stable across processes.
        let _ = std::fs::remove_file(&self.port_path);
    }
}

fn paths() -> Result<(PathBuf, PathBuf)> {
    // The lock identifies the visible application, not a database. Otherwise
    // --state-database could open a second desktop window beside the owner.
    let directory = crate::app_paths::project_dirs()
        .map(|dirs| dirs.data_local_dir().to_path_buf())
        .context("could not determine the operating system application data directory")?;
    std::fs::create_dir_all(&directory)
        .with_context(|| format!("creating {}", directory.display()))?;
    Ok((
        directory.join("instance.lock"),
        directory.join("instance.port"),
    ))
}

/// Take ownership of the instance slot, or ask the running owner to raise.
/// `Ok(None)` means another instance already owns the slot and was notified.
pub(crate) fn request_or_own() -> Result<Option<InstanceGuard>> {
    let (lock_path, port_path) = paths()?;
    request_paths(&lock_path, &port_path)
}

fn request_paths(lock_path: &Path, port_path: &Path) -> Result<Option<InstanceGuard>> {
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(lock_path)
        .with_context(|| format!("opening {}", lock_path.display()))?;
    match lock.try_lock_exclusive() {
        Ok(()) => {
            let listener = TcpListener::bind(("127.0.0.1", 0))
                .context("binding the Lunchpail instance socket")?;
            let port = listener
                .local_addr()
                .context("reading the Lunchpail instance socket address")?
                .port();
            // Publish the port atomically so a racing second launch never
            // reads a half-written number.
            let temporary = port_path.with_extension("port.tmp");
            std::fs::write(&temporary, port.to_string())
                .with_context(|| format!("writing {}", temporary.display()))?;
            std::fs::rename(&temporary, &port_path)
                .with_context(|| format!("publishing {}", port_path.display()))?;
            std::thread::Builder::new()
                .name("lunchpail-instance".into())
                .spawn(move || {
                    for stream in listener.incoming().flatten() {
                        accept(stream);
                    }
                })
                .context("spawning the Lunchpail instance listener")?;
            Ok(Some(InstanceGuard {
                _lock: lock,
                port_path: port_path.to_path_buf(),
            }))
        }
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
            raise_existing(&port_path);
            Ok(None)
        }
        Err(error) => Err(error).context("locking the Lunchpail instance slot"),
    }
}

fn accept(mut stream: TcpStream) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let mut request = String::new();
    if let Ok(clone) = stream.try_clone() {
        let _ = BufReader::new(clone).read_line(&mut request);
    }
    let response = if request.trim() == format!("restart {}", std::process::id()) {
        RESTART_REQUESTED.store(true, Ordering::SeqCst);
        b"restarting\n".as_slice()
    } else if request.trim() == "raise" {
        RAISE_REQUESTED.store(true, Ordering::SeqCst);
        b"ok\n".as_slice()
    } else {
        b"unsupported\n".as_slice()
    };
    let _ = stream.write_all(response);
    let _ = stream.flush();
}

fn raise_existing(port_path: &Path) {
    // The owner publishes the port just after locking, so a simultaneous
    // launch retries briefly before giving up; the lock still prevents a
    // second library from starting either way.
    for _ in 0..20 {
        if let Ok(text) = std::fs::read_to_string(port_path)
            && let Ok(port) = text.trim().parse::<u16>()
            && let Ok(mut stream) = TcpStream::connect(("127.0.0.1", port))
        {
            let _ = stream.write_all(b"raise\n");
            let _ = stream.flush();
            return;
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

/// Consume a pending raise request. Called from the Qt thread.
pub(crate) fn take_raise_signal() -> bool {
    RAISE_REQUESTED.swap(false, Ordering::SeqCst)
}

fn take_restart_signal() -> bool {
    if !RESTART_REQUESTED.swap(false, Ordering::SeqCst) {
        return false;
    }
    if let Err(error) = crate::emulator_session::detach_owned_ui() {
        eprintln!("LUNCHPAIL_DEV_RESTART_DEFERRED: {error:#}");
        return false;
    }
    RESTART_CONSUMED.store(true, Ordering::SeqCst);
    true
}

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        type SingleInstance = super::SingleInstanceRust;

        /// True once per request from a later launch that this window should be
        /// raised and focused.
        #[qinvokable]
        fn take_raise_request(self: &SingleInstance) -> bool;

        #[qinvokable]
        fn take_restart_request(self: &SingleInstance) -> bool;
    }
}

#[derive(Default)]
pub struct SingleInstanceRust;

impl qobject::SingleInstance {
    pub fn take_restart_request(&self) -> bool {
        take_restart_signal()
    }

    pub fn take_raise_request(&self) -> bool {
        take_raise_signal()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    #[ignore = "subprocess fixture, invoked by restart_handoff_preserves_game_and_retires_host"]
    fn restart_process_fixture() {
        let root = std::env::var_os("LUNCHPAIL_RESTART_TEST_ROOT").expect("isolated fixture root");
        let root = PathBuf::from(root);
        assert!(root.is_dir());
        assert_eq!(
            std::env::var_os("XDG_DATA_HOME"),
            Some(root.join("data").into_os_string())
        );
        let guard = request_or_own()
            .unwrap()
            .expect("fixture owns the visible instance");
        if crate::emulator_session::active().unwrap().is_none() {
            let command: Vec<String> = std::env::var("LUNCHPAIL_RESTART_TEST_COMMAND")
                .ok()
                .map(|value| serde_json::from_str(&value).unwrap())
                .unwrap_or_else(|| vec!["sleep".into(), "60".into()]);
            let session = crate::emulator_session::reserve("restart-test", "Restart test").unwrap();
            let mut child = std::process::Command::new(&command[0])
                .args(&command[1..])
                .spawn()
                .unwrap();
            crate::emulator_session::mark_running(
                &session.token,
                child.id(),
                "restart-test",
                None,
                None,
            )
            .unwrap();
            let worker = crate::emulator_session::LaunchWorker::new();
            std::thread::spawn(move || {
                let _worker = worker;
                let status = child.wait().unwrap();
                eprintln!("RESTART_TEST_GAME_EXIT {status}");
                crate::emulator_session::clear(&session.token).unwrap();
            });
        }
        std::fs::write(root.join(format!("ready-{}", std::process::id())), b"ready").unwrap();
        while !take_restart_signal() {
            std::thread::sleep(Duration::from_millis(10));
        }
        drop(guard);
        crate::emulator_session::finish_owned_session_after_ui_restart();
    }

    #[cfg(unix)]
    #[test]
    fn restart_handoff_preserves_game_and_retires_host() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let spawn = || {
            std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "single_instance::tests::restart_process_fixture",
                    "--ignored",
                    "--nocapture",
                ])
                .env("LUNCHPAIL_RESTART_TEST_ROOT", root)
                .env("XDG_DATA_HOME", root.join("data"))
                .env("XDG_CONFIG_HOME", root.join("config"))
                .env("XDG_CACHE_HOME", root.join("cache"))
                .spawn()
                .unwrap()
        };
        let ready = |pid: u32| {
            for _ in 0..200 {
                if root.join(format!("ready-{pid}")).is_file() {
                    return;
                }
                std::thread::sleep(Duration::from_millis(25));
            }
            panic!("fixture did not become ready");
        };
        let mut owner = spawn();
        ready(owner.id());
        let state = root.join("data/lunchpail");
        let read_session = || {
            serde_json::from_slice::<serde_json::Value>(
                &std::fs::read(state.join("emulator-session.json")).unwrap(),
            )
            .unwrap()
        };
        let original = read_session();
        assert_eq!(original["game_id"], "restart-test");
        assert_eq!(original["owner"]["pid"], owner.id());
        let game_pid = original["process"]["pid"].as_u64().unwrap() as i32;
        std::thread::sleep(Duration::from_millis(500));
        // Wrong-target requests must never detach somebody else's UI.
        assert!(
            prepare_restart_at(
                &state.join("instance.lock"),
                &state.join("instance.port"),
                owner.id() + 1
            )
            .is_err()
        );
        prepare_restart_at(
            &state.join("instance.lock"),
            &state.join("instance.port"),
            owner.id(),
        )
        .unwrap();
        assert!(
            owner.try_wait().unwrap().is_none(),
            "launch host must outlive its UI"
        );
        let mut replacement = spawn();
        ready(replacement.id());
        let adopted = read_session();
        assert_eq!(adopted["process"], original["process"]);
        assert_eq!(adopted["token"], original["token"]);
        assert_eq!(adopted["ui_detached"], true);
        prepare_restart_at(
            &state.join("instance.lock"),
            &state.join("instance.port"),
            replacement.id(),
        )
        .unwrap();
        assert!(replacement.wait().unwrap().success());
        assert!(owner.try_wait().unwrap().is_none());
        assert_eq!(
            unsafe { libc::kill(game_pid, 0) },
            0,
            "game survives two UI replacements"
        );
        let session = serde_json::from_value::<crate::emulator_session::Session>(adopted).unwrap();
        crate::emulator_session::stop(&session).unwrap();
        assert!(
            owner.wait().unwrap().success(),
            "host retires after the game exits"
        );
        assert!(!state.join("emulator-session.json").exists());
    }

    #[test]
    fn second_request_raises_the_owner_and_takes_no_new_slot() {
        let directory = tempfile::tempdir().unwrap();
        let lock = directory.path().join("instance.lock");
        let port = directory.path().join("instance.port");
        RAISE_REQUESTED.store(false, Ordering::SeqCst);
        let owner = request_paths(&lock, &port).unwrap();
        assert!(owner.is_some(), "the first request owns the slot");
        // The owner is listening once request_paths returns, so a second
        // request connects and asks it to raise without taking a new slot.
        let second = request_paths(&lock, &port).unwrap();
        assert!(second.is_none(), "the second request must not start a copy");
        let mut raised = false;
        for _ in 0..100 {
            if take_raise_signal() {
                raised = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(raised, "the owner must receive the raise request");
        assert!(!take_raise_signal(), "the raise signal is consumed once");
    }
}
