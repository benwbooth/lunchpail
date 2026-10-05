use crate::couch_speech::{self, Event};
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use std::{
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
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
        #[qproperty(bool, ready)]
        #[qproperty(bool, busy)]
        #[qproperty(bool, listening)]
        #[qproperty(QString, status)]
        #[qproperty(QString, transcript)]
        type CouchSpeechModel = super::CouchSpeechModelRust;
        #[qinvokable]
        fn prepare(self: Pin<&mut CouchSpeechModel>);
        #[qinvokable]
        fn start(self: Pin<&mut CouchSpeechModel>);
        #[qinvokable]
        fn stop(self: Pin<&mut CouchSpeechModel>);
        #[qinvokable]
        fn cancel(self: Pin<&mut CouchSpeechModel>);
        #[qinvokable]
        fn poll(self: Pin<&mut CouchSpeechModel>);
        #[qinvokable]
        fn refresh(self: Pin<&mut CouchSpeechModel>);
        #[qsignal]
        fn completed(self: Pin<&mut CouchSpeechModel>, text: QString);
    }
}

pub struct CouchSpeechModelRust {
    ready: bool,
    busy: bool,
    listening: bool,
    status: QString,
    transcript: QString,
    backend: String,
    control: Arc<AtomicU8>,
    receiver: Option<mpsc::Receiver<Event>>,
}
impl Default for CouchSpeechModelRust {
    fn default() -> Self {
        let ready = couch_speech::installed();
        Self {
            ready,
            busy: false,
            listening: false,
            status: QString::from(if ready {
                "Ready. Press the microphone button to speak."
            } else {
                "Choose a speech model in Settings → Local AI & voice, or download the selected model here."
            }),
            transcript: QString::default(),
            backend: String::new(),
            control: Arc::new(AtomicU8::new(0)),
            receiver: None,
        }
    }
}
impl Drop for CouchSpeechModelRust {
    fn drop(&mut self) {
        self.control.store(couch_speech::CANCEL, Ordering::Relaxed);
    }
}
impl qobject::CouchSpeechModel {
    pub fn refresh(mut self: Pin<&mut Self>) {
        let ready = crate::local_ai::speech_ready();
        self.as_mut().set_ready(ready);
        if !*self.busy() {
            self.set_status(QString::from(if ready {
                "Ready. Press the microphone button to speak."
            } else {
                "Choose or download a speech model in Settings → Local AI & voice."
            }));
        }
    }
    fn begin(mut self: Pin<&mut Self>, prepare: bool) {
        if *self.busy() {
            return;
        }
        let control = Arc::new(AtomicU8::new(0));
        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().control = control.clone();
        self.as_mut().rust_mut().receiver = Some(rx);
        self.as_mut().rust_mut().backend.clear();
        self.as_mut().set_busy(true);
        self.as_mut().set_transcript(QString::default());
        self.as_mut().set_status(QString::from(if prepare {
            "Preparing local speech model…"
        } else {
            "Opening microphone…"
        }));
        std::thread::spawn(move || {
            let result = if prepare {
                couch_speech::prepare(&control, &tx).map(|()| Event::Ready)
            } else {
                couch_speech::listen(control, &tx).map(Event::Finished)
            };
            let _ = tx.send(result.unwrap_or_else(|error| {
                Event::Error(format!("{error:#}"), couch_speech::model_is_valid())
            }));
        });
    }
    pub fn prepare(self: Pin<&mut Self>) {
        self.begin(true);
    }
    pub fn start(self: Pin<&mut Self>) {
        if *self.ready() {
            self.begin(false);
        }
    }
    pub fn stop(self: Pin<&mut Self>) {
        self.control.store(couch_speech::STOP, Ordering::Relaxed);
    }
    pub fn cancel(mut self: Pin<&mut Self>) {
        self.control.store(couch_speech::CANCEL, Ordering::Relaxed);
        // Drop this session's receiver so late partials cannot edit a newer query.
        self.as_mut().rust_mut().receiver = None;
        self.as_mut().set_busy(false);
        self.as_mut().set_listening(false);
        self.as_mut()
            .set_status(QString::from("Voice search cancelled. Microphone off."));
    }
    pub fn poll(mut self: Pin<&mut Self>) {
        let events: Vec<_> = self
            .receiver
            .as_ref()
            .map(|rx| rx.try_iter().collect())
            .unwrap_or_default();
        for event in events {
            match event {
                Event::Status(text) => self.as_mut().set_status(QString::from(&text)),
                Event::Ready => {
                    self.as_mut().set_ready(true);
                    self.as_mut().set_busy(false);
                    self.as_mut().set_status(QString::from(
                        "Ready. Press the microphone button to speak.",
                    ));
                }
                Event::Listening => {
                    self.as_mut().set_listening(true);
                    self.as_mut().set_status(QString::from(
                        "Listening locally… Speak a game title. Stops after a pause or 15 seconds.",
                    ));
                }
                Event::Decoding => {
                    self.as_mut().set_listening(false);
                    self.as_mut()
                        .set_status(QString::from("Microphone off. Transcribing locally…"));
                }
                Event::Text(text) => self.as_mut().set_transcript(QString::from(&text)),
                Event::Backend(text) => self.as_mut().rust_mut().backend = text,
                Event::Finished(text) => {
                    self.as_mut().set_transcript(QString::from(&text));
                    self.as_mut().set_listening(false);
                    self.as_mut().set_busy(false);
                    let status = if text.is_empty() {
                        "No speech detected. Try again, or type a question.".to_owned()
                    } else if self.backend.is_empty() {
                        "Microphone off. Transcribed locally on CPU.".to_owned()
                    } else {
                        format!("Microphone off. Transcribed locally on {}.", self.backend)
                    };
                    self.as_mut().set_status(QString::from(status));
                    self.as_mut().completed(QString::from(text));
                }
                Event::Error(error, model_ready) => {
                    self.as_mut().set_listening(false);
                    self.as_mut().set_busy(false);
                    self.as_mut().set_ready(model_ready);
                    self.as_mut().set_status(QString::from(&error));
                }
            }
        }
    }
}
