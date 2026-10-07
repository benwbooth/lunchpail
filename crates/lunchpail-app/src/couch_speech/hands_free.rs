//! Wake-phrase gating happens locally, before any text reaches search or AI.
use super::*;

#[derive(Default)]
struct WakeGate {
    until: Option<Instant>,
}

impl WakeGate {
    fn accept(&mut self, text: &str, now: Instant) -> (bool, Option<String>) {
        let words: Vec<_> = text.split_whitespace().collect();
        let normalized: Vec<_> = words
            .iter()
            .map(|word| {
                word.trim_matches(|c: char| !c.is_alphanumeric())
                    .to_lowercase()
            })
            .collect();
        let offset = usize::from(
            normalized
                .first()
                .is_some_and(|w| matches!(w.as_str(), "ok" | "okay")),
        );
        let rest = &normalized[offset..];
        let wake_words = if rest.first().is_some_and(|w| w == "lunchpail") {
            1
        } else if rest.len() >= 2
            && rest[0] == "lunch"
            && matches!(rest[1].as_str(), "pail" | "pale")
        {
            2
        } else {
            0
        };
        if wake_words > 0 {
            let query = words[offset + wake_words..].join(" ");
            if query.is_empty() {
                self.until = Some(now + Duration::from_secs(8));
                (true, None)
            } else {
                self.until = None;
                (false, Some(query))
            }
        } else if !text.trim().is_empty() && self.until.take().is_some_and(|until| now <= until) {
            (false, Some(text.trim().to_owned()))
        } else {
            self.until = self.until.filter(|until| now <= *until);
            (self.until.is_some(), None)
        }
    }
}

fn accepted(gate: &mut WakeGate, text: &str, wake_word: bool) -> (bool, Option<String>) {
    if wake_word {
        gate.accept(text, Instant::now())
    } else {
        (
            false,
            (!text.trim().is_empty()).then(|| text.trim().to_owned()),
        )
    }
}
fn deliver(gate: &mut WakeGate, text: &str, wake_word: bool, tx: &mpsc::Sender<Event>) {
    let (awake, command) = accepted(gate, text, wake_word);
    let _ = tx.send(Event::Wake(awake));
    if let Some(query) = command {
        let _ = tx.send(Event::Command(query));
    }
}

pub fn listen_hands_free(control: Arc<AtomicU8>, tx: &mpsc::Sender<Event>) -> Result<String> {
    listen_hands_free_with_vocabulary(control, tx, &[])
}

pub fn listen_hands_free_with_vocabulary(
    control: Arc<AtomicU8>,
    tx: &mpsc::Sender<Event>,
    vocabulary: &[String],
) -> Result<String> {
    use lunchpail_ai::{Request, models, worker};
    let settings = crate::local_ai::settings()?;
    let wake_word = crate::conversation::settings::load()?.wake_word;
    let model = models::find(&settings.speech)?;
    let whisper = model.engine == models::Engine::Whisper;
    // Load/verify before opening the microphone. No hidden secondary model.
    let mut decoder = if whisper {
        None
    } else {
        Some(StreamingDecoder::new(recognizer_with_vocabulary(
            vocabulary,
        )?))
    };
    let model_path = if whisper {
        Some(crate::local_ai::with_cancel(&control, |cancel| {
            models::verify(&crate::local_ai::data_dir()?, model, cancel)
        })?)
    } else {
        None
    };
    let mut session = if whisper {
        Some(worker::Session::new(
            &worker::bundled_directory()?,
            worker::Kind::Speech,
            &settings.compute,
        )?)
    } else {
        None
    };
    let device = cpal::default_host()
        .default_input_device()
        .context("No microphone found. Connect one and enable hands-free again.")?;
    let supported = device
        .default_input_config()
        .context("Cannot open the default microphone")?;
    let config = supported.config();
    let rate = config.sample_rate.0;
    ensure!(
        (8000..=192000).contains(&rate),
        "Unsupported microphone sample rate"
    );
    let (audio_tx, audio_rx) = mpsc::sync_channel(32);
    let (error_tx, error_rx) = mpsc::channel();
    let microphone = match supported.sample_format() {
        cpal::SampleFormat::F32 => capture::<f32>(&device, &config, audio_tx, error_tx)?,
        cpal::SampleFormat::I16 => capture::<i16>(&device, &config, audio_tx, error_tx)?,
        cpal::SampleFormat::U16 => capture::<u16>(&device, &config, audio_tx, error_tx)?,
        format => bail!("Unsupported microphone sample format: {format}"),
    };
    if control.load(Ordering::Relaxed) != 0 {
        return Ok(String::new());
    }
    microphone
        .play()
        .context("Microphone access denied or device unavailable")?;
    let _ = tx.send(Event::Listening);
    let _ = tx.send(Event::Wake(false));
    let mut gate = WakeGate::default();
    let mut activity = ActivityGate::new(rate, if whisper { 900 } else { 1200 });
    let mut audio = Vec::new();
    while control.load(Ordering::Relaxed) == 0 {
        if let Ok(error) = error_rx.try_recv() {
            bail!("Microphone disconnected: {error}");
        }
        if gate.until.is_some_and(|until| Instant::now() > until) {
            gate.until = None;
            let _ = tx.send(Event::Wake(false));
        }
        let Ok(samples) = audio_rx.recv_timeout(Duration::from_millis(50)) else {
            continue;
        };
        for input in activity.push(&samples) {
            if control.load(Ordering::Relaxed) != 0 {
                break;
            }
            if let Input::Silent(silent) = &input {
                let _ = tx.send(Event::InputSilent(*silent));
            }
            if matches!(&input, Input::Start(_) | Input::End) {
                let _ = tx.send(Event::SpeechActive(matches!(&input, Input::Start(_))));
            }
            if matches!(&input, Input::Start(_)) && !wake_word {
                let _ = tx.send(Event::Wake(true));
            }
            if let Some(decoder) = decoder.as_mut() {
                match decoder.accept(input, rate, &control) {
                    Some(Transcript::Partial(text)) if !wake_word => {
                        let _ = tx.send(Event::Text(text));
                    }
                    Some(Transcript::Final(text)) => {
                        if control.load(Ordering::Relaxed) == 0 {
                            deliver(&mut gate, &text, wake_word, tx);
                        }
                    }
                    _ => {}
                }
                continue;
            }
            match input {
                Input::Start(samples) | Input::Audio(samples) => {
                    audio.extend(
                        samples
                            .into_iter()
                            .take((rate as usize * 15).saturating_sub(audio.len())),
                    );
                }
                Input::Silent(_) => {}
                Input::End => {
                    if audio.is_empty() {
                        continue;
                    }
                    let request = Request::Transcribe {
                        model: model_path.as_ref().unwrap().clone(),
                        device: None,
                        samples: resample_16khz(&audio, rate),
                        language: if model.id == "whisper-small" {
                            "auto"
                        } else {
                            "en"
                        }
                        .into(),
                        vocabulary: vocabulary.to_vec(),
                    };
                    let reply = crate::local_ai::with_cancel(&control, |cancel| {
                        session.as_mut().unwrap().request(&request, cancel)
                    })?;
                    if control.load(Ordering::Relaxed) != 0 {
                        break;
                    }
                    deliver(&mut gate, &reply.text, wake_word, tx);
                    audio.clear();
                    // Don't interpret queued audio from the inference interval as a new command.
                    while audio_rx.try_recv().is_ok() {}
                }
            }
        }
    }
    drop(microphone);
    Ok(String::new())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn conversation_mode_preserves_natural_requests_without_a_prefix() {
        let mut gate = WakeGate::default();
        for text in [
            "search for super mario bros",
            "play the game",
            "yes please",
            "turn the music down",
        ] {
            assert_eq!(accepted(&mut gate, text, false), (false, Some(text.into())));
        }
        assert_eq!(accepted(&mut gate, "   ", false), (false, None));
        assert_eq!(accepted(&mut gate, "play the game", true), (false, None));
    }
    #[test]
    fn only_prefix_wake_phrases_allow_commands() {
        let now = Instant::now();
        let mut gate = WakeGate::default();
        for text in [
            "Mario",
            "I bought a lunch pail",
            "okay Mario",
            "lunchpailish Mario",
        ] {
            assert_eq!(gate.accept(text, now), (false, None));
        }
        for text in [
            "Lunchpail Mario",
            "OK Lunchpail Mario",
            "Okay, lunch pail Mario",
            "lunch pale Mario",
        ] {
            assert_eq!(gate.accept(text, now), (false, Some("Mario".into())));
        }
    }
    #[test]
    fn standalone_wake_arms_once_and_expires() {
        let now = Instant::now();
        let mut gate = WakeGate::default();
        assert_eq!(gate.accept("OK Lunchpail", now), (true, None));
        assert_eq!(
            gate.accept("Sonic 2", now + Duration::from_secs(3)),
            (false, Some("Sonic 2".into()))
        );
        assert_eq!(
            gate.accept("Mario", now + Duration::from_secs(4)),
            (false, None)
        );
        gate.accept("Lunchpail", now);
        assert_eq!(
            gate.accept("Mario", now + Duration::from_secs(9)),
            (false, None)
        );
    }

    #[test]
    #[ignore = "Requires installed speech model and an explicit WAV fixture; never opens a microphone"]
    fn real_streaming_recognizer_gates_fixture() {
        let file = std::env::var("LUNCHPAIL_WAKE_TEST_WAV").expect("explicit WAV fixture");
        let expected = std::env::var("LUNCHPAIL_WAKE_TEST_EXPECT").expect("expected command");
        let wave = sherpa_onnx::Wave::read(&file).unwrap();
        let recognizer = recognizer().unwrap();
        let mut stream = recognizer.create_stream();
        let mut gate = WakeGate::default();
        let mut commands = Vec::new();
        let mut samples = wave.samples().to_vec();
        samples.extend(vec![0.0; wave.sample_rate() as usize * 3]);
        for chunk in samples.chunks(1600) {
            stream.accept_waveform(wave.sample_rate(), chunk);
            while recognizer.is_ready(&stream) {
                recognizer.decode(&stream);
            }
            if recognizer.is_endpoint(&stream) {
                let text = recognizer.get_result(&stream).unwrap().text;
                eprintln!("WAKE_FIXTURE_TRANSCRIPT={text:?}");
                if let (_, Some(command)) = gate.accept(&text, Instant::now()) {
                    commands.push(command.to_lowercase());
                }
                stream = recognizer.create_stream();
            }
        }
        assert_eq!(commands, vec![expected.to_lowercase()]);
    }
}
