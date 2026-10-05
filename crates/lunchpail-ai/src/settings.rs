use crate::models::{self, Engine};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use std::{io::Write, path::Path};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub struct Settings {
    pub assistant: String,
    pub speech: String,
    pub compute: String,
    pub hands_free: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            assistant: String::new(),
            speech: "sherpa-zipformer-en".into(),
            compute: "auto".into(),
            hands_free: false,
        }
    }
}

impl Settings {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            matches!(self.compute.as_str(), "auto" | "cpu" | "gpu"),
            "Unknown compute preference"
        );
        if !self.assistant.is_empty() {
            ensure!(
                models::find(&self.assistant)?.engine == Engine::Llama,
                "Select an assistant model"
            );
        }
        if !self.speech.is_empty() {
            ensure!(
                models::find(&self.speech)?.engine != Engine::Llama,
                "Select a speech model"
            );
        }
        Ok(())
    }
    pub fn load(data: &Path) -> Result<Self> {
        let bytes = match std::fs::read(data.join("ai/settings.json")) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(e) => return Err(e).context("Reading local AI settings"),
        };
        let settings: Self = serde_json::from_slice(&bytes).context("Reading local AI settings")?;
        settings.validate()?;
        Ok(settings)
    }
    pub fn save(&self, data: &Path) -> Result<()> {
        self.validate()?;
        let dir = data.join("ai");
        std::fs::create_dir_all(&dir)?;
        let mut file = tempfile::NamedTempFile::new_in(&dir)?;
        file.write_all(&serde_json::to_vec_pretty(self)?)?;
        file.as_file().sync_all()?;
        file.persist(dir.join("settings.json"))
            .map_err(|e| e.error)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn settings_round_trip_and_reject_wrong_engine_or_arbitrary_paths() {
        let dir = tempfile::tempdir().unwrap();
        let mut settings = Settings::load(dir.path()).unwrap();
        assert!(settings.assistant.is_empty());
        assert!(!settings.hands_free);
        settings.assistant = "qwen3-4b".into();
        settings.speech = "whisper-base-en".into();
        settings.hands_free = true;
        settings.save(dir.path()).unwrap();
        assert_eq!(Settings::load(dir.path()).unwrap(), settings);
        settings.assistant = "whisper-base-en".into();
        assert!(settings.save(dir.path()).is_err());
        settings.assistant = "../../model".into();
        assert!(settings.save(dir.path()).is_err());
        assert_eq!(Settings::load(dir.path()).unwrap().assistant, "qwen3-4b");
    }
    #[test]
    fn existing_settings_never_enable_microphone_implicitly() {
        let settings: Settings = serde_json::from_str(
            r#"{"assistant":"","speech":"sherpa-zipformer-en","compute":"auto"}"#,
        )
        .unwrap();
        assert!(!settings.hands_free);
    }
}
