use crate::{
    conversation::{
        self, Event, Message,
        settings::{self, Provider, Settings},
    },
    local_ai,
};
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }
    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, busy)]
        #[qproperty(bool, ready)]
        #[qproperty(QString, status)]
        #[qproperty(QString, result_json)]
        #[qproperty(QString, history_json)]
        #[qproperty(QString, config_json)]
        #[qproperty(QString, models_json)]
        #[qproperty(QString, setup_status)]
        #[qproperty(bool, setup_busy)]
        #[qproperty(bool, key_saved)]
        #[qproperty(i32, turn_number)]
        type AssistantModel = super::AssistantModelRust;
        #[qinvokable]
        fn ask(self: Pin<&mut AssistantModel>, question: QString);
        #[qinvokable]
        fn cancel(self: Pin<&mut AssistantModel>);
        #[qinvokable]
        fn clear(self: Pin<&mut AssistantModel>);
        #[qinvokable]
        fn refresh(self: Pin<&mut AssistantModel>);
        #[qinvokable]
        fn poll(self: Pin<&mut AssistantModel>);
        #[qinvokable]
        fn configure(self: Pin<&mut AssistantModel>, value: QString);
        #[qinvokable]
        fn save_api_key(self: Pin<&mut AssistantModel>, value: QString);
        #[qinvokable]
        fn discover_models(self: Pin<&mut AssistantModel>);
        #[qinvokable]
        fn complete_tool(self: Pin<&mut AssistantModel>, id: QString, result: QString);
        #[qsignal]
        fn tool_requested(
            self: Pin<&mut AssistantModel>,
            id: QString,
            name: QString,
            arguments: QString,
        );
        #[qsignal]
        fn replied(self: Pin<&mut AssistantModel>, text: QString);
    }
}
pub struct AssistantModelRust {
    busy: bool,
    ready: bool,
    status: QString,
    result_json: QString,
    history_json: QString,
    config_json: QString,
    models_json: QString,
    setup_status: QString,
    setup_busy: bool,
    key_saved: bool,
    turn_number: i32,
    cancel: Arc<AtomicBool>,
    receiver: Option<mpsc::Receiver<Event>>,
    setup_receiver: Option<mpsc::Receiver<Result<Value, String>>>,
    history: Vec<Message>,
    pending: HashMap<String, mpsc::Sender<Value>>,
}
fn configuration(settings: &Settings) -> String {
    let mut settings = settings.clone();
    for provider in [
        Provider::Builtin,
        Provider::Codex,
        Provider::ClaudeCode,
        Provider::Ollama,
        Provider::Openai,
        Provider::Anthropic,
        Provider::Compatible,
    ] {
        let profile = settings.profile_for(provider);
        settings.profiles.insert(provider.key().into(), profile);
    }
    serde_json::to_string(&settings).unwrap_or_else(|_| "{}".into())
}
fn ready(settings: &Settings) -> bool {
    match settings.provider {
        Provider::Builtin => local_ai::data_dir()
            .ok()
            .zip(local_ai::settings().ok())
            .is_some_and(|(data, s)| {
                lunchpail_ai::models::find(&s.assistant)
                    .is_ok_and(|m| lunchpail_ai::models::installed(&data, m))
            }),
        Provider::Codex | Provider::ClaudeCode => !settings.profile().executable.trim().is_empty(),
        _ => !settings.profile().model.trim().is_empty(),
    }
}
impl Default for AssistantModelRust {
    fn default() -> Self {
        let config = settings::load().unwrap_or_default();
        Self {
            busy: false,
            ready: ready(&config),
            status: QString::from("Ask me to search, play, browse or help with setup."),
            result_json: QString::from("{}"),
            history_json: QString::from("[]"),
            config_json: QString::from(configuration(&config)),
            models_json: QString::from("[]"),
            setup_status: QString::default(),
            setup_busy: false,
            key_saved: false,
            turn_number: 0,
            cancel: Arc::new(AtomicBool::new(false)),
            receiver: None,
            setup_receiver: None,
            history: Vec::new(),
            pending: HashMap::new(),
        }
    }
}
impl Drop for AssistantModelRust {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}
impl qobject::AssistantModel {
    fn update_history(mut self: Pin<&mut Self>) {
        while self.history.len() > 20
            || self.history.iter().map(|m| m.content.len()).sum::<usize>() > 24000
        {
            self.as_mut().rust_mut().history.remove(0);
        }
        while self.history.first().is_some_and(|m| m.role != "user") {
            self.as_mut().rust_mut().history.remove(0);
        }
        let json = serde_json::to_string(&self.history).unwrap_or_else(|_| "[]".into());
        self.set_history_json(QString::from(json));
    }
    pub fn refresh(mut self: Pin<&mut Self>) {
        match settings::load() {
            Ok(settings) => {
                self.as_mut().set_ready(ready(&settings));
                self.as_mut()
                    .set_config_json(QString::from(configuration(&settings)));
                self.as_mut()
                    .set_key_saved(settings::key(settings.provider).ok().flatten().is_some());
                if !*self.ready() {
                    self.set_status(QString::from("Choose a provider/model in Settings → AI & voice, or install a bundled local model."));
                }
            }
            Err(e) => {
                self.as_mut().set_ready(false);
                self.set_status(QString::from(format!("{e:#}")));
            }
        }
    }
    pub fn configure(mut self: Pin<&mut Self>, value: QString) {
        let previous_provider = settings::load().ok().map(|s| s.provider);
        let result = (|| -> anyhow::Result<()> {
            let settings: Settings = serde_json::from_str(&value.to_string())?;
            settings.save(&local_ai::data_dir()?)
        })();
        match result {
            Ok(()) => {
                if settings::load().ok().map(|s| s.provider) != previous_provider {
                    self.as_mut().cancel();
                    self.as_mut().rust_mut().setup_receiver = None;
                    self.as_mut().set_setup_busy(false);
                    self.as_mut().set_models_json(QString::from("[]"));
                }
                self.as_mut().refresh();
                self.set_setup_status(QString::from(
                    "Preferences saved. Use Test conversation to verify the connection.",
                ));
            }
            Err(e) => {
                self.set_setup_status(QString::from(format!("Could not save preferences: {e:#}")))
            }
        }
    }
    pub fn save_api_key(mut self: Pin<&mut Self>, value: QString) {
        let result =
            settings::load().and_then(|s| settings::save_key(s.provider, &value.to_string()));
        match result {
            Ok(()) => {
                self.as_mut().refresh();
                self.set_setup_status(QString::from("API key updated in the OS keyring."));
            }
            Err(_) => self.set_setup_status(QString::from(
                "Could not store the key. Check that your OS keyring is unlocked.",
            )),
        }
    }
    pub fn discover_models(mut self: Pin<&mut Self>) {
        if self.setup_busy {
            return;
        }
        let Ok(settings) = settings::load() else {
            return;
        };
        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().setup_receiver = Some(rx);
        self.as_mut().set_setup_busy(true);
        self.set_setup_status(QString::from("Reading available models…"));
        std::thread::spawn(move || {
            let _ = tx.send(conversation::models(&settings).map_err(|e| format!("{e:#}")));
        });
    }
    pub fn complete_tool(mut self: Pin<&mut Self>, id: QString, result: QString) {
        if let Some(reply) = self.as_mut().rust_mut().pending.remove(&id.to_string()) {
            let value = serde_json::from_str(&result.to_string())
                .unwrap_or_else(|_| json!({"error":"App returned invalid tool results"}));
            let _ = reply.send(value);
        }
    }
    pub fn cancel(mut self: Pin<&mut Self>) {
        self.cancel.store(true, Ordering::Relaxed);
        self.as_mut().rust_mut().receiver = None;
        self.as_mut().rust_mut().pending.clear();
        self.as_mut().set_busy(false);
        self.set_status(QString::from(
            "Conversation stopped. Actions already completed are not undone.",
        ));
    }
    pub fn clear(mut self: Pin<&mut Self>) {
        self.as_mut().cancel();
        self.as_mut().rust_mut().history.clear();
        self.as_mut().update_history();
        self.as_mut().set_result_json(QString::from("{}"));
        self.set_status(QString::from(
            "New conversation. Ask me to search, play, browse or help with setup.",
        ));
    }
    pub fn ask(mut self: Pin<&mut Self>, question: QString) {
        if self.busy {
            return;
        }
        let question = question.to_string().trim().to_owned();
        if question.is_empty() {
            return;
        }
        if question.len() > 4000 {
            self.set_status(QString::from("Keep messages under 4,000 characters."));
            return;
        }
        self.as_mut().refresh();
        if !self.ready {
            return;
        }
        let Ok(settings) = settings::load() else {
            return;
        };
        self.as_mut().rust_mut().history.push(Message {
            role: "user".into(),
            content: question,
        });
        self.as_mut().update_history();
        let history = self.history.clone();
        let cancel = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().cancel = cancel.clone();
        self.as_mut().rust_mut().receiver = Some(rx);
        let turn = self.turn_number.saturating_add(1);
        self.as_mut().set_turn_number(turn);
        self.as_mut().set_busy(true);
        self.as_mut().set_result_json(QString::from("{}"));
        self.set_status(QString::from(format!(
            "Connecting to {}…",
            settings.provider.label()
        )));
        std::thread::spawn(move || {
            let result = conversation::ask(
                &settings,
                &history,
                &mut conversation::Runtime::new(&cancel, &tx),
            )
            .map_err(|e| format!("{e:#}"));
            let _ = tx.send(Event::Finished(result));
        });
    }
    pub fn poll(mut self: Pin<&mut Self>) {
        let setup = self.setup_receiver.as_ref().and_then(|r| r.try_recv().ok());
        if let Some(result) = setup {
            self.as_mut().rust_mut().setup_receiver = None;
            self.as_mut().set_setup_busy(false);
            match result {
                Ok(models) => {
                    self.as_mut()
                        .set_models_json(QString::from(models.to_string()));
                    self.as_mut().set_setup_status(QString::from("Model list received. Choose a tool-capable model, then test a conversation."));
                }
                Err(e) => self.as_mut().set_setup_status(QString::from(e)),
            }
        }
        let events: Vec<_> = self
            .receiver
            .as_ref()
            .map(|r| r.try_iter().collect())
            .unwrap_or_default();
        for event in events {
            match event {
                Event::Status(text) => self.as_mut().set_status(QString::from(text)),
                Event::Tool {
                    id,
                    name,
                    arguments,
                    reply,
                } => {
                    self.as_mut().rust_mut().pending.insert(id.clone(), reply);
                    self.as_mut().tool_requested(
                        QString::from(id),
                        QString::from(name),
                        QString::from(arguments.to_string()),
                    );
                }
                Event::Finished(result) => {
                    self.as_mut().set_busy(false);
                    self.as_mut().rust_mut().receiver = None;
                    self.as_mut().rust_mut().pending.clear();
                    let (text, error) = match result {
                        Ok(text) => (text, false),
                        Err(e) => (format!("I couldn't complete that request. {e}"), true),
                    };
                    self.as_mut().rust_mut().history.push(Message {
                        role: "assistant".into(),
                        content: text.clone(),
                    });
                    self.as_mut().update_history();
                    self.as_mut().set_result_json(QString::from(
                        json!({"message":text,"error":error,"games":[],"patches":[]}).to_string(),
                    ));
                    self.as_mut().set_status(QString::from(if error {
                        "Check the reply for setup or connection details."
                    } else {
                        "Ready for your next request."
                    }));
                    self.as_mut().replied(QString::from(text));
                }
            }
        }
    }
}
