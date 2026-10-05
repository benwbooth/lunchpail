use anyhow::{Context, Result};
use lunchpail_ai::{models, settings::Settings};
use std::path::PathBuf;

pub fn data_dir() -> Result<PathBuf> {
    Ok(crate::app_paths::project_dirs()
        .context("Application data directory unavailable")?
        .data_local_dir()
        .to_owned())
}

pub fn settings() -> Result<Settings> {
    Settings::load(&data_dir()?)
}

/// Stop finishes an utterance; Cancel also aborts inference/downloads.
pub fn with_cancel<T>(
    control: &std::sync::atomic::AtomicU8,
    operation: impl FnOnce(&std::sync::atomic::AtomicBool) -> T,
) -> T {
    use std::sync::atomic::{AtomicBool, Ordering};
    let cancel = AtomicBool::new(control.load(Ordering::Relaxed) == crate::couch_speech::CANCEL);
    let finished = AtomicBool::new(false);
    struct Finish<'a>(&'a AtomicBool);
    impl Drop for Finish<'_> {
        fn drop(&mut self) {
            self.0.store(true, Ordering::Relaxed);
        }
    }
    std::thread::scope(|scope| {
        scope.spawn(|| {
            while !finished.load(Ordering::Relaxed) {
                if control.load(Ordering::Relaxed) == crate::couch_speech::CANCEL {
                    cancel.store(true, Ordering::Relaxed);
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
        });
        let _finish = Finish(&finished);
        operation(&cancel)
    })
}

pub fn speech_ready() -> bool {
    data_dir()
        .ok()
        .zip(settings().ok())
        .is_some_and(|(data, settings)| {
            models::find(&settings.speech).is_ok_and(|model| models::installed(&data, model))
        })
}
