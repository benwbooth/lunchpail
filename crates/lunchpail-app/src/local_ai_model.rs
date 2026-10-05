use crate::local_ai;
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use lunchpail_ai::{
    models::{self, Engine},
    settings::Settings,
    worker::{self, Kind},
};
use std::{
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
        #[qproperty(QString, models_json)]
        #[qproperty(QString, assistant_model)]
        #[qproperty(QString, speech_model)]
        #[qproperty(QString, compute)]
        #[qproperty(QString, status)]
        #[qproperty(QString, hardware)]
        #[qproperty(f64, progress)]
        #[qproperty(bool, busy)]
        #[qproperty(bool, assistant_ready)]
        #[qproperty(bool, speech_ready)]
        type LocalAiModel = super::LocalAiModelRust;
        #[qinvokable]
        fn select_assistant(self: Pin<&mut LocalAiModel>, id: QString);
        #[qinvokable]
        fn select_speech(self: Pin<&mut LocalAiModel>, id: QString);
        #[qinvokable]
        fn select_compute(self: Pin<&mut LocalAiModel>, mode: QString);
        #[qinvokable]
        fn download_selected(self: Pin<&mut LocalAiModel>);
        #[qinvokable]
        fn detect_hardware(self: Pin<&mut LocalAiModel>);
        #[qinvokable]
        fn cancel(self: Pin<&mut LocalAiModel>);
        #[qinvokable]
        fn poll(self: Pin<&mut LocalAiModel>);
    }
}

enum Event {
    Progress(f64, String),
    Finished(Result<(), String>),
    Hardware(String),
}
pub struct LocalAiModelRust {
    models_json: QString,
    assistant_model: QString,
    speech_model: QString,
    compute: QString,
    status: QString,
    hardware: QString,
    progress: f64,
    busy: bool,
    assistant_ready: bool,
    speech_ready: bool,
    cancel: Arc<AtomicBool>,
    receiver: Option<mpsc::Receiver<Event>>,
}
impl Default for LocalAiModelRust {
    fn default() -> Self {
        let result = local_ai::settings();
        let status = result.as_ref().err().map(|e| format!("{e:#}")).unwrap_or_else(|| "Choose a model to download it. Everything runs locally; no account or separate server needed.".into());
        let settings = result.unwrap_or_default();
        let ready = |id: &str| {
            local_ai::data_dir()
                .is_ok_and(|data| models::find(id).is_ok_and(|m| models::installed(&data, m)))
        };
        let catalog: Vec<_> = models::MODELS.iter().map(|m| serde_json::json!({"id":m.id,"name":m.name,"description":m.description,"assistant":m.engine == Engine::Llama,"bytes":models::bytes(m),"license":m.license})).collect();
        Self {
            models_json: QString::from(serde_json::to_string(&catalog).unwrap_or_default()),
            assistant_ready: ready(&settings.assistant),
            speech_ready: ready(&settings.speech),
            assistant_model: QString::from(settings.assistant),
            speech_model: QString::from(settings.speech),
            compute: QString::from(settings.compute),
            status: QString::from(status),
            hardware: QString::from("CPU always available. Check hardware to detect GPUs."),
            progress: 0.0,
            busy: false,
            cancel: Arc::new(AtomicBool::new(false)),
            receiver: None,
        }
    }
}
impl Drop for LocalAiModelRust {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}

impl qobject::LocalAiModel {
    fn persist(mut self: Pin<&mut Self>, field: &str, value: QString) {
        let result = (|| -> anyhow::Result<Settings> {
            let data = local_ai::data_dir()?;
            let mut settings = Settings::load(&data)?;
            match field {
                "assistant" => settings.assistant = value.to_string(),
                "speech" => settings.speech = value.to_string(),
                _ => settings.compute = value.to_string(),
            }
            settings.save(&data)?;
            Ok(settings)
        })();
        match result {
            Ok(settings) => {
                self.as_mut()
                    .set_assistant_model(QString::from(settings.assistant));
                self.as_mut()
                    .set_speech_model(QString::from(settings.speech));
                self.as_mut().set_compute(QString::from(settings.compute));
                self.as_mut().refresh_ready();
                if field != "compute" {
                    self.download_selected();
                }
            }
            Err(e) => self.set_status(QString::from(format!("{e:#}"))),
        }
    }
    fn refresh_ready(mut self: Pin<&mut Self>) {
        let ready = |id: &str| {
            local_ai::data_dir()
                .is_ok_and(|data| models::find(id).is_ok_and(|m| models::installed(&data, m)))
        };
        let assistant = ready(&self.assistant_model().to_string());
        let speech = ready(&self.speech_model().to_string());
        self.as_mut().set_assistant_ready(assistant);
        self.set_speech_ready(speech);
    }
    pub fn select_assistant(self: Pin<&mut Self>, id: QString) {
        self.persist("assistant", id);
    }
    pub fn select_speech(self: Pin<&mut Self>, id: QString) {
        self.persist("speech", id);
    }
    pub fn select_compute(self: Pin<&mut Self>, mode: QString) {
        self.persist("compute", mode);
    }
    pub fn cancel(mut self: Pin<&mut Self>) {
        self.cancel.store(true, Ordering::Relaxed);
        self.as_mut().rust_mut().receiver = None;
        self.as_mut().set_busy(false);
        self.set_status(QString::from(
            "Cancelled. Partial downloads will resume when you retry.",
        ));
    }
    fn begin(mut self: Pin<&mut Self>) -> (Arc<AtomicBool>, mpsc::Sender<Event>) {
        self.cancel.store(true, Ordering::Relaxed);
        let cancel = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().cancel = cancel.clone();
        self.as_mut().rust_mut().receiver = Some(rx);
        self.as_mut().set_busy(true);
        self.set_progress(0.0);
        (cancel, tx)
    }
    pub fn download_selected(mut self: Pin<&mut Self>) {
        let (cancel, tx) = self.as_mut().begin();
        self.set_status(QString::from("Preparing selected models…"));
        std::thread::spawn(move || {
            let result = (|| -> anyhow::Result<()> {
                let data = local_ai::data_dir()?;
                let settings = Settings::load(&data)?;
                for id in [&settings.assistant, &settings.speech] {
                    if id.is_empty() {
                        continue;
                    }
                    let model = models::find(id)?;
                    models::download(&data, model, &cancel, |done, total, detail| {
                        let _ = tx.send(Event::Progress(
                            done as f64 / total as f64,
                            format!(
                                "{} — {detail} ({:.0}%)",
                                model.name,
                                100.0 * done as f64 / total as f64
                            ),
                        ));
                    })?;
                }
                Ok(())
            })()
            .map_err(|e| format!("{e:#}"));
            let _ = tx.send(Event::Finished(result));
        });
    }
    pub fn detect_hardware(mut self: Pin<&mut Self>) {
        let (cancel, tx) = self.as_mut().begin();
        self.set_status(QString::from("Checking bundled CPU/GPU runtimes…"));
        std::thread::spawn(move || {
            let result = (|| -> anyhow::Result<()> {
                let directory = worker::bundled_directory()?;
                let mut lines = vec!["CPU fallback is bundled.".to_owned()];
                for (name, kind) in [("Assistant", Kind::Llm), ("Speech", Kind::Speech)] {
                    match worker::probe(&directory, kind, &cancel) {
                        Ok(reply) if !reply.devices.is_empty() => {
                            for device in reply.devices {
                                lines.push(format!(
                                    "{name}: {} · {} · {:.1} GB",
                                    device.name,
                                    device.backend,
                                    device.memory_bytes as f64 / 1e9
                                ));
                            }
                        }
                        Ok(_) => lines.push(format!(
                            "{name}: no compatible GPU detected; use CPU or Auto."
                        )),
                        Err(e) => {
                            lines.push(format!("{name}: GPU unavailable ({e:#}); use CPU or Auto."))
                        }
                    }
                }
                let _ = tx.send(Event::Hardware(lines.join("\n")));
                Ok(())
            })()
            .map_err(|e| format!("{e:#}"));
            let _ = tx.send(Event::Finished(result));
        });
    }
    pub fn poll(mut self: Pin<&mut Self>) {
        let events: Vec<_> = self
            .receiver
            .as_ref()
            .map(|rx| rx.try_iter().collect())
            .unwrap_or_default();
        for event in events {
            match event {
                Event::Progress(progress, text) => {
                    self.as_mut().set_progress(progress);
                    self.as_mut().set_status(QString::from(text));
                }
                Event::Hardware(text) => self.as_mut().set_hardware(QString::from(text)),
                Event::Finished(result) => {
                    self.as_mut().set_busy(false);
                    self.as_mut().refresh_ready();
                    self.as_mut()
                        .set_status(QString::from(result.err().unwrap_or_else(|| {
                            "Ready. Your selections are saved automatically.".into()
                        })));
                    self.as_mut().rust_mut().receiver = None;
                }
            }
        }
    }
}
