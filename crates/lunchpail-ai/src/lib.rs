//! Bundled local inference: pinned model downloads and a bounded worker protocol.
//! No daemon, Python runtime, account, or Ollama installation is required.
pub mod models;
pub mod settings;
pub mod worker;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_MESSAGE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Device {
    pub id: usize,
    pub name: String,
    pub backend: String,
    pub memory_bytes: u64,
    pub free_bytes: u64,
    pub integrated: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum Request {
    Probe,
    Generate {
        model: PathBuf,
        device: Option<usize>,
        system: String,
        prompt: String,
        /// Structured turns preserve the distinction between a user's request,
        /// completed assistant calls and tool observations. Empty keeps the
        /// original single-prompt protocol for non-conversational callers.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        messages: Vec<ChatMessage>,
        schema: serde_json::Value,
        max_tokens: u32,
    },
    Transcribe {
        model: PathBuf,
        device: Option<usize>,
        /// Mono 16 kHz samples, kept in memory and never written as audio files.
        samples: Vec<f32>,
        language: String,
    },
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Reply {
    pub version: u32,
    pub text: String,
    pub device: String,
    pub devices: Vec<Device>,
    pub error: String,
    pub warning: String,
}

impl Reply {
    pub fn success(text: String, device: String) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            text,
            device,
            ..Self::default()
        }
    }
    pub fn error(error: impl std::fmt::Display) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            error: error.to_string(),
            ..Self::default()
        }
    }
}

/// Entry point shared by native workers. stdout is exclusively JSON-lines;
/// native engine diagnostics go to stderr. Requests and responses are bounded.
pub fn serve(mut handle: impl FnMut(Request) -> anyhow::Result<Reply>) -> anyhow::Result<()> {
    use std::io::{BufRead, Read, Write};
    let stdin = std::io::stdin();
    let mut reader = stdin.lock();
    let mut stdout = std::io::stdout().lock();
    loop {
        let mut bytes = Vec::new();
        let count = reader
            .by_ref()
            .take((MAX_MESSAGE_BYTES + 1) as u64)
            .read_until(b'\n', &mut bytes)?;
        if count == 0 {
            break;
        }
        anyhow::ensure!(
            bytes.len() <= MAX_MESSAGE_BYTES,
            "Inference request is too large"
        );
        let reply = serde_json::from_slice::<Request>(&bytes)
            .map_err(anyhow::Error::from)
            .and_then(&mut handle)
            .unwrap_or_else(Reply::error);
        serde_json::to_writer(&mut stdout, &reply)?;
        writeln!(stdout)?;
        stdout.flush()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn generation_messages_are_optional_and_round_trip_on_the_wire() {
        let mut value = serde_json::json!({"operation":"generate","model":"model.gguf","device":null,
            "system":"system","prompt":"question","schema":{},"max_tokens":32});
        let request: Request = serde_json::from_value(value.clone()).unwrap();
        assert!(matches!(&request, Request::Generate { messages, .. } if messages.is_empty()));
        assert!(serde_json::to_value(request).unwrap().get("messages").is_none());
        value["prompt"] = serde_json::json!("");
        value["messages"] = serde_json::json!([
            {"role":"user","content":"open a game"},
            {"role":"assistant","content":"{\"get_context\":{}}"},
            {"role":"tool","content":"{\"games\":[]}"}
        ]);
        let request: Request = serde_json::from_value(value.clone()).unwrap();
        assert_eq!(serde_json::to_value(request).unwrap(), value);
    }
}
