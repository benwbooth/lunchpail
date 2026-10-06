//! Provider preferences contain no credentials. Secrets stay in the OS keyring.
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io::Write, path::Path};

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    #[default]
    Builtin,
    Codex,
    ClaudeCode,
    Ollama,
    Openai,
    Anthropic,
    Compatible,
}
impl Provider {
    pub fn key(self) -> &'static str {
        match self {
            Self::Builtin => "builtin",
            Self::Codex => "codex",
            Self::ClaudeCode => "claude_code",
            Self::Ollama => "ollama",
            Self::Openai => "openai",
            Self::Anthropic => "anthropic",
            Self::Compatible => "compatible",
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Builtin => "Bundled local model",
            Self::Codex => "Codex sign-in",
            Self::ClaudeCode => "Claude Code sign-in",
            Self::Ollama => "Ollama",
            Self::Openai => "OpenAI API",
            Self::Anthropic => "Anthropic API",
            Self::Compatible => "OpenAI-compatible server",
        }
    }
    pub fn uses_key(self) -> bool {
        matches!(self, Self::Openai | Self::Anthropic | Self::Compatible)
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct Profile {
    pub model: String,
    pub endpoint: String,
    pub executable: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct Settings {
    pub provider: Provider,
    pub profiles: BTreeMap<String, Profile>,
    pub spoken_replies: bool,
    pub captions: bool,
    pub wake_word: bool,
    pub voice: String,
    pub voice_engine: String,
    pub voice_rate: f64,
    pub voice_volume: f64,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            provider: Provider::Builtin,
            profiles: BTreeMap::new(),
            spoken_replies: true,
            captions: true,
            wake_word: false,
            voice: String::new(),
            voice_engine: String::new(),
            voice_rate: 0.0,
            voice_volume: 0.85,
        }
    }
}
impl Settings {
    pub fn profile_for(&self, provider: Provider) -> Profile {
        self.profiles
            .get(provider.key())
            .cloned()
            .unwrap_or_else(|| Profile {
                endpoint: match provider {
                    Provider::Openai => "https://api.openai.com/v1",
                    Provider::Anthropic => "https://api.anthropic.com/v1",
                    Provider::Ollama => "http://127.0.0.1:11434",
                    Provider::Compatible => "http://127.0.0.1:8080/v1",
                    _ => "",
                }
                .into(),
                executable: match provider {
                    Provider::Codex => "codex",
                    Provider::ClaudeCode => "claude",
                    _ => "",
                }
                .into(),
                ..Profile::default()
            })
    }
    pub fn profile(&self) -> Profile {
        self.profile_for(self.provider)
    }
    pub fn validate(&self) -> Result<()> {
        ensure!(
            self.voice.len() <= 200 && self.voice_engine.len() <= 80,
            "Voice name is too long"
        );
        ensure!(
            self.voice_rate.is_finite() && (-1.0..=1.0).contains(&self.voice_rate),
            "Voice rate must be between -1 and 1"
        );
        ensure!(
            self.voice_volume.is_finite() && (0.0..=1.0).contains(&self.voice_volume),
            "Voice volume must be between 0 and 1"
        );
        for (key, profile) in &self.profiles {
            let provider: Provider = serde_json::from_value(serde_json::json!(key))
                .context("Unknown assistant provider")?;
            ensure!(
                profile.model.len() <= 200 && !profile.model.contains(['\n', '\r', '\0']),
                "Invalid model name"
            );
            ensure!(
                profile.executable.len() <= 2048
                    && !profile.executable.contains(['\n', '\r', '\0']),
                "Invalid executable path"
            );
            if matches!(provider, Provider::Codex | Provider::ClaudeCode) {
                ensure!(
                    !profile.executable.trim().is_empty(),
                    "Choose the provider's executable"
                );
            } else if provider != Provider::Builtin {
                validate_endpoint(&profile.endpoint)?;
            }
        }
        Ok(())
    }
    pub fn load(data: &Path) -> Result<Self> {
        let bytes = match std::fs::read(data.join("ai/assistant.json")) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(e) => return Err(e).context("Reading assistant preferences"),
        };
        let settings: Self =
            serde_json::from_slice(&bytes).context("Reading assistant preferences")?;
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
        file.persist(dir.join("assistant.json"))
            .map_err(|e| e.error)?;
        Ok(())
    }
}

pub fn validate_endpoint(endpoint: &str) -> Result<url::Url> {
    ensure!(endpoint.len() <= 2048, "Server URL is too long");
    let url = url::Url::parse(endpoint).context("Enter a full server URL")?;
    ensure!(
        url.username().is_empty()
            && url.password().is_none()
            && url.query().is_none()
            && url.fragment().is_none(),
        "Keep credentials, query parameters and fragments out of the server URL"
    );
    let loopback = url.host_str().is_some_and(|h| {
        h == "localhost"
            || h == "[::1]"
            || h == "::1"
            || h.parse::<std::net::IpAddr>()
                .is_ok_and(|ip| ip.is_loopback())
    });
    ensure!(
        url.scheme() == "https" || (url.scheme() == "http" && loopback),
        "Remote AI servers require HTTPS; HTTP is allowed only on localhost"
    );
    Ok(url)
}

pub fn load() -> Result<Settings> {
    Settings::load(&crate::local_ai::data_dir()?)
}
pub fn key(provider: Provider) -> Result<Option<String>> {
    let environment = match provider {
        Provider::Openai => "OPENAI_API_KEY",
        Provider::Anthropic => "ANTHROPIC_API_KEY",
        Provider::Compatible => "LUNCHPAIL_ASSISTANT_API_KEY",
        _ => return Ok(None),
    };
    if let Ok(value) = std::env::var(environment) {
        if !value.trim().is_empty() {
            return Ok(Some(value));
        }
    }
    crate::settings::load_secret(
        &format!("assistant-{}", provider.key()),
        "assistant API key",
    )
}
pub fn save_key(provider: Provider, key: &str) -> Result<()> {
    ensure!(
        provider.uses_key(),
        "This provider uses its own sign-in, not an API key"
    );
    ensure!(
        key.len() <= 8192 && !key.contains(['\n', '\r', '\0']),
        "Invalid API key"
    );
    crate::settings::save_secret(
        &format!("assistant-{}", provider.key()),
        key.trim(),
        "assistant API key",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn provider_and_voice_preferences_round_trip_without_keys() {
        let dir = tempfile::tempdir().unwrap();
        let mut settings = Settings::load(dir.path()).unwrap();
        assert!(!settings.wake_word);
        settings.provider = Provider::Ollama;
        let mut profile = settings.profile();
        profile.model = "chosen-model".into();
        settings.profiles.insert("ollama".into(), profile);
        settings.voice = "My voice".into();
        settings.save(dir.path()).unwrap();
        assert_eq!(Settings::load(dir.path()).unwrap(), settings);
        assert!(serde_json::from_str::<Settings>(r#"{"api_key":"secret"}"#).is_err());
    }
    #[test]
    fn endpoints_reject_accidental_credential_exposure() {
        for url in [
            "http://example.org/v1",
            "https://secret@example.org",
            "file:///tmp/test",
            "https://example.org?key=secret",
        ] {
            assert!(validate_endpoint(url).is_err(), "{url}");
        }
        for url in [
            "http://127.0.0.1:11434",
            "http://[::1]:8080/v1",
            "https://example.org/v1",
        ] {
            assert!(validate_endpoint(url).is_ok(), "{url}");
        }
    }
}
