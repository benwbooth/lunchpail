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

fn deliver(gate: &mut WakeGate, text: &str, tx: &mpsc::Sender<Event>) {
    let (awake, command) = gate.accept(text, Instant::now());
    let _ = tx.send(Event::Wake(awake));
    if let Some(query) = command {
        let _ = tx.send(Event::Command(query));
    }
}

pub fn listen_hands_free(control: Arc<AtomicU8>, tx: &mpsc::Sender<Event>) -> Result<String> {
    use lunchpail_ai::{Request, models, worker};
    let settings = crate::local_ai::settings()?;
    let model = models::find(&settings.speech)?;
    let whisper = model.engine == models::Engine::Whisper;
    // Load/verify before opening the microphone. No hidden secondary model.
    let recognizer = if whisper { None } else { Some(recognizer()?) };
    let mut stream = recognizer.as_ref().map(|r| r.create_stream());
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
    let mut audio = Vec::new();
    let mut last_voice = None;
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
        if let (Some(recognizer), Some(stream_ref)) = (&recognizer, &stream) {
            stream_ref.accept_waveform(rate as i32, &samples);
            while recognizer.is_ready(stream_ref) && control.load(Ordering::Relaxed) == 0 {
                recognizer.decode(stream_ref);
            }
            if recognizer.is_endpoint(stream_ref) {
                let text = recognizer
                    .get_result(stream_ref)
                    .map(|r| r.text)
                    .unwrap_or_default();
                deliver(&mut gate, &text, tx);
                stream = Some(recognizer.create_stream());
            }
        } else {
            let energy = samples.iter().map(|x| x * x).sum::<f32>() / samples.len().max(1) as f32;
            if energy > 0.000036 {
                last_voice = Some(Instant::now());
            }
            audio.extend(
                samples
                    .into_iter()
                    .take((rate as usize * 15).saturating_sub(audio.len())),
            );
            if last_voice.is_none() {
                // Keep 250 ms of pre-roll, not an ever-growing ambient recording.
                let excess = audio.len().saturating_sub(rate as usize / 4);
                audio.drain(..excess);
            } else if audio.len() >= rate as usize * 15
                || last_voice.is_some_and(|last| last.elapsed() > Duration::from_millis(900))
            {
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
                };
                let reply = crate::local_ai::with_cancel(&control, |cancel| {
                    session.as_mut().unwrap().request(&request, cancel)
                })?;
                if control.load(Ordering::Relaxed) != 0 {
                    break;
                }
                deliver(&mut gate, &reply.text, tx);
                audio.clear();
                last_voice = None;
                // Don't interpret queued audio from the inference interval as a new command.
                while audio_rx.try_recv().is_ok() {}
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
