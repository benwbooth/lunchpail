use crate::{
    assistant::{self, Event},
    local_ai,
};
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
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
        #[qproperty(bool, busy)]
        #[qproperty(bool, ready)]
        #[qproperty(QString, status)]
        #[qproperty(QString, result_json)]
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
    }
}
pub struct AssistantModelRust {
    busy: bool,
    ready: bool,
    status: QString,
    result_json: QString,
    cancel: Arc<AtomicBool>,
    receiver: Option<mpsc::Receiver<Event>>,
    prior: String,
    question: String,
}
fn ready() -> bool {
    local_ai::data_dir()
        .ok()
        .zip(local_ai::settings().ok())
        .is_some_and(|(data, settings)| {
            lunchpail_ai::models::find(&settings.assistant)
                .is_ok_and(|m| lunchpail_ai::models::installed(&data, m))
        })
}
impl Default for AssistantModelRust {
    fn default() -> Self {
        Self {
            busy: false,
            ready: ready(),
            status: QString::from(
                "Ask about games and translation patches. Recommendations only; nothing is installed or launched.",
            ),
            result_json: QString::from("{}"),
            cancel: Arc::new(AtomicBool::new(false)),
            receiver: None,
            prior: String::new(),
            question: String::new(),
        }
    }
}
impl Drop for AssistantModelRust {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}
impl qobject::AssistantModel {
    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().set_ready(ready());
        if !*self.ready() {
            self.set_status(QString::from(
                "Choose and download an assistant model in Settings → Local AI & voice.",
            ));
        }
    }
    pub fn cancel(mut self: Pin<&mut Self>) {
        self.cancel.store(true, Ordering::Relaxed);
        self.as_mut().rust_mut().receiver = None;
        self.as_mut().set_busy(false);
        self.set_status(QString::from(
            "Assistant cancelled. Nothing was installed or launched.",
        ));
    }
    pub fn clear(mut self: Pin<&mut Self>) {
        self.as_mut().cancel();
        self.as_mut().rust_mut().prior.clear();
        self.as_mut().rust_mut().question.clear();
        self.as_mut().set_result_json(QString::from("{}"));
        self.set_status(QString::from(
            "New conversation. Ask about games or translation patches.",
        ));
    }
    pub fn ask(mut self: Pin<&mut Self>, question: QString) {
        if *self.busy() {
            return;
        }
        self.as_mut().refresh();
        if !*self.ready() {
            return;
        }
        let question = question.to_string();
        if question.trim().is_empty() {
            return;
        }
        let prior = self.prior.clone();
        let cancel = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().cancel = cancel.clone();
        self.as_mut().rust_mut().receiver = Some(rx);
        self.as_mut().rust_mut().question = question.clone();
        self.as_mut().set_busy(true);
        self.as_mut().set_result_json(QString::from("{}"));
        self.set_status(QString::from("Starting the bundled local assistant…"));
        std::thread::spawn(move || {
            let result = assistant::ask(&question, &prior, &cancel, |s| {
                let _ = tx.send(Event::Status(s));
            })
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
                Event::Status(text) => self.as_mut().set_status(QString::from(text)),
                Event::Finished(result) => {
                    self.as_mut().set_busy(false);
                    self.as_mut().rust_mut().receiver = None;
                    match result {
                        Ok(result) => {
                            let prior = format!(
                                "User: {}\nAssistant: {}\nCatalog games: {}",
                                self.question,
                                result["message"].as_str().unwrap_or(""),
                                result["games"]
                            );
                            self.as_mut().rust_mut().prior = prior.chars().take(3500).collect();
                            let warning = result["warning"].as_str().unwrap_or("");
                            self.as_mut().set_status(QString::from(format!(
                                "Answered locally on {}. {}",
                                result["device"].as_str().unwrap_or("local runtime"),
                                warning
                            )));
                            self.as_mut()
                                .set_result_json(QString::from(result.to_string()));
                        }
                        Err(error) => self.as_mut().set_status(QString::from(error)),
                    }
                }
            }
        }
    }
}
