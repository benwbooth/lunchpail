//! Local, opt-in streaming search. Audio is never saved or sent over the network.
use anyhow::{Context, Result, bail, ensure};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use sha2::{Digest, Sha256};
use sherpa_onnx::{OnlineRecognizer, OnlineRecognizerConfig};
use std::{
    io::Read,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};

pub const STOP: u8 = 1;
pub const CANCEL: u8 = 2;
mod hands_free;
pub use hands_free::listen_hands_free;
pub use hands_free::listen_hands_free_with_vocabulary;
mod hotwords;
const FILES: [(&str, &str, u64); 4] = [
    (
        "encoder-epoch-99-avg-1.int8.onnx",
        "32c98281c7bd8b63e3e142d007251b37f120572e8fdea9a4f5a79ce22b10ec4f",
        187823992,
    ),
    (
        "decoder-epoch-99-avg-1.onnx",
        "9da02b77cb08826756ec6a88635f35a40374e4164e7c6359121a9145958a6ceb",
        2092566,
    ),
    (
        "joiner-epoch-99-avg-1.int8.onnx",
        "831477d390e59a61f1b6a6f763b9903e6c6366ff6034f1ddba613be82637122f",
        259335,
    ),
    (
        "tokens.txt",
        "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb",
        5048,
    ),
];

pub enum Event {
    Status(String),
    Ready,
    Listening,
    Decoding,
    Backend(String),
    Text(String),
    Finished(String),
    Error(String, bool),
    Wake(bool),
    Command(String),
}

pub fn model_dir() -> Result<PathBuf> {
    Ok(crate::app_paths::project_dirs()
        .context("Application data directory unavailable")?
        .data_local_dir()
        .join("speech/zipformer-en-2023-06-21"))
}

pub fn installed() -> bool {
    crate::local_ai::speech_ready()
}

fn valid_file(path: &Path, digest: &str, size: u64) -> bool {
    let Ok(mut file) = std::fs::File::open(path) else {
        return false;
    };
    if !file.metadata().is_ok_and(|meta| meta.len() == size) {
        return false;
    }
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        match file.read(&mut buffer) {
            Ok(0) => return hex::encode(hash.finalize()) == digest,
            Ok(n) => hash.update(&buffer[..n]),
            Err(_) => return false,
        }
    }
}

pub fn model_is_valid() -> bool {
    let Ok(settings) = crate::local_ai::settings() else {
        return false;
    };
    let Ok(data) = crate::local_ai::data_dir() else {
        return false;
    };
    lunchpail_ai::models::find(&settings.speech).is_ok_and(|model| {
        lunchpail_ai::models::verify(&data, model, &std::sync::atomic::AtomicBool::new(false))
            .is_ok()
    })
}

pub fn prepare(control: &AtomicU8, tx: &mpsc::Sender<Event>) -> Result<()> {
    let settings = crate::local_ai::settings()?;
    let data = crate::local_ai::data_dir()?;
    let model = lunchpail_ai::models::find(&settings.speech)
        .context("Choose a speech model in Settings → Local AI & voice")?;
    crate::local_ai::with_cancel(control, |cancel| {
        lunchpail_ai::models::download(&data, model, cancel, |done, total, detail| {
            let _ = tx.send(Event::Status(format!(
                "{}: {detail} ({:.0}%)",
                model.name,
                done as f64 * 100.0 / total as f64
            )));
        })
    })
}

fn recognizer() -> Result<OnlineRecognizer> {
    recognizer_with_vocabulary(&[])
}

fn recognizer_with_vocabulary(vocabulary: &[String]) -> Result<OnlineRecognizer> {
    let dir = model_dir()?;
    for (name, digest, size) in FILES {
        ensure!(
            valid_file(&dir.join(name), digest, size),
            "Voice model is missing or damaged. Download it again."
        );
    }
    let mut config = OnlineRecognizerConfig::default();
    config.model_config.transducer.encoder =
        Some(dir.join(FILES[0].0).to_string_lossy().into_owned());
    config.model_config.transducer.decoder =
        Some(dir.join(FILES[1].0).to_string_lossy().into_owned());
    config.model_config.transducer.joiner =
        Some(dir.join(FILES[2].0).to_string_lossy().into_owned());
    config.model_config.tokens = Some(dir.join(FILES[3].0).to_string_lossy().into_owned());
    config.model_config.provider = Some("cpu".into());
    config.model_config.num_threads = 2;
    config.decoding_method = Some("greedy_search".into());
    let phrases = hotwords::phrases(vocabulary);
    let mut bpe_file = None;
    if !phrases.is_empty() {
        // sherpa-onnx contextual biasing requires transducer beam search.
        // Use the actual model vocabulary: the native C API defaults to a CJK
        // tokenizer, which splits pre-tokenized English pieces incorrectly.
        // The native encoder reads this tiny bundled file during create().
        use std::io::Write;
        let mut file = tempfile::NamedTempFile::new()?;
        file.write_all(hotwords::BPE_VOCAB.as_bytes())?;
        file.flush()?;
        config.model_config.modeling_unit = Some("bpe".into());
        config.model_config.bpe_vocab = Some(file.path().to_string_lossy().into_owned());
        bpe_file = Some(file);
        config.decoding_method = Some("modified_beam_search".into());
        config.max_active_paths = 4;
        config.hotwords_score = 1.5;
        config.hotwords_buf = Some(phrases.into_bytes());
    }
    config.enable_endpoint = true;
    config.rule1_min_trailing_silence = 4.0;
    config.rule2_min_trailing_silence = 1.2;
    config.rule3_min_utterance_length = 15.0;
    let recognizer = OnlineRecognizer::create(&config).context("Could not load the local speech recognizer");
    drop(bpe_file);
    recognizer
}

fn mono<T: cpal::Sample + Copy>(data: &[T], channels: usize) -> Vec<f32>
where
    f32: cpal::FromSample<T>,
{
    data.chunks_exact(channels)
        .map(|frame| {
            frame
                .iter()
                .map(|sample| sample.to_sample::<f32>())
                .sum::<f32>()
                / channels as f32
        })
        .collect()
}

fn capture<T: cpal::SizedSample + Copy>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    tx: mpsc::SyncSender<Vec<f32>>,
    errors: mpsc::Sender<cpal::StreamError>,
) -> Result<cpal::Stream>
where
    f32: cpal::FromSample<T>,
{
    let channels = config.channels as usize;
    Ok(device.build_input_stream(
        config,
        move |data: &[T], _| {
            // Bounded queue: a slow decoder must never accumulate unbounded audio.
            let _ = tx.try_send(mono(data, channels));
        },
        move |error| {
            let _ = errors.send(error);
        },
        None,
    )?)
}

pub fn listen(control: Arc<AtomicU8>, tx: &mpsc::Sender<Event>) -> Result<String> {
    listen_with_vocabulary(control, tx, &[])
}

pub fn listen_with_vocabulary(control: Arc<AtomicU8>, tx: &mpsc::Sender<Event>, vocabulary: &[String]) -> Result<String> {
    let settings = crate::local_ai::settings()?;
    let model = lunchpail_ai::models::find(&settings.speech)
        .context("Choose a speech model in Settings → Local AI & voice")?;
    if model.engine == lunchpail_ai::models::Engine::Whisper {
        return listen_whisper(control, tx, &settings, model, vocabulary);
    }
    let recognizer = recognizer_with_vocabulary(vocabulary)?;
    ensure!(
        control.load(Ordering::Relaxed) == 0,
        "Voice search cancelled"
    );
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .context("No microphone found. Connect one and try again.")?;
    let supported = device
        .default_input_config()
        .context("Cannot open the default microphone")?;
    let config = supported.config();
    let sample_rate = config.sample_rate.0 as i32;
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
    let stream = recognizer.create_stream();
    microphone
        .play()
        .context("Microphone access denied or device unavailable")?;
    let _ = tx.send(Event::Listening);
    let started = Instant::now();
    let mut previous = String::new();
    while control.load(Ordering::Relaxed) == 0 && started.elapsed() < Duration::from_secs(15) {
        if let Ok(error) = error_rx.try_recv() {
            bail!("Microphone disconnected: {error}");
        }
        if let Ok(samples) = audio_rx.recv_timeout(Duration::from_millis(50)) {
            stream.accept_waveform(sample_rate, &samples);
            while recognizer.is_ready(&stream) {
                recognizer.decode(&stream);
            }
            let text = recognizer
                .get_result(&stream)
                .map(|result| result.text)
                .unwrap_or_default();
            if text != previous {
                previous = text.clone();
                let _ = tx.send(Event::Text(text.trim().to_owned()));
            }
            if recognizer.is_endpoint(&stream) {
                break;
            }
        }
    }
    drop(microphone);
    if control.load(Ordering::Relaxed) == CANCEL {
        return Ok(String::new());
    }
    stream.accept_waveform(sample_rate, &vec![0.0; sample_rate as usize / 2]);
    stream.input_finished();
    while recognizer.is_ready(&stream) {
        recognizer.decode(&stream);
    }
    Ok(recognizer
        .get_result(&stream)
        .map(|result| result.text.trim().to_owned())
        .unwrap_or_default())
}

fn listen_whisper(
    control: Arc<AtomicU8>,
    tx: &mpsc::Sender<Event>,
    settings: &lunchpail_ai::settings::Settings,
    model: &lunchpail_ai::models::Model,
    vocabulary: &[String],
) -> Result<String> {
    use lunchpail_ai::{
        Request, models,
        worker::{self, Kind},
    };
    let model_path = crate::local_ai::with_cancel(&control, |cancel| {
        models::verify(&crate::local_ai::data_dir()?, model, cancel)
    })?;
    let runtime = worker::bundled_directory()?;
    ensure!(
        control.load(Ordering::Relaxed) == 0,
        "Voice search cancelled"
    );
    let device = cpal::default_host()
        .default_input_device()
        .context("No microphone found. Connect one and try again.")?;
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
    let started = Instant::now();
    let mut last_voice = None;
    let mut audio = Vec::with_capacity(rate as usize * 15);
    while control.load(Ordering::Relaxed) == 0 && started.elapsed() < Duration::from_secs(15) {
        if let Ok(error) = error_rx.try_recv() {
            bail!("Microphone disconnected: {error}");
        }
        if let Ok(samples) = audio_rx.recv_timeout(Duration::from_millis(40)) {
            let energy = samples.iter().map(|x| x * x).sum::<f32>() / samples.len().max(1) as f32;
            if energy > 0.000036 {
                last_voice = Some(Instant::now());
            }
            audio.extend(
                samples
                    .into_iter()
                    .take((rate as usize * 15).saturating_sub(audio.len())),
            );
            if audio.len() >= rate as usize * 15 {
                break;
            }
        }
        if last_voice.is_some_and(|last| last.elapsed() > Duration::from_millis(1200))
            || (last_voice.is_none() && started.elapsed() > Duration::from_secs(4))
        {
            break;
        }
    }
    drop(microphone); // Release the microphone BEFORE inference or CPU retry.
    let _ = tx.send(Event::Decoding);
    if control.load(Ordering::Relaxed) == CANCEL || last_voice.is_none() {
        return Ok(String::new());
    }
    let samples = resample_16khz(&audio, rate);
    if samples.len() < 1600 {
        return Ok(String::new());
    }
    let request = Request::Transcribe {
        model: model_path,
        device: None,
        samples,
        language: if model.id == "whisper-small" {
            "auto"
        } else {
            "en"
        }
        .into(),
        vocabulary: vocabulary.to_vec(),
    };
    let reply = crate::local_ai::with_cancel(&control, |cancel| {
        worker::one_shot(&runtime, Kind::Speech, &settings.compute, &request, cancel)
    })?;
    let detail = if reply.warning.is_empty() {
        reply.device.clone()
    } else {
        format!("{} — {}", reply.device, reply.warning)
    };
    let _ = tx.send(Event::Backend(detail));
    Ok(reply.text)
}

/// Windowed-sinc low-pass resampling also rejects frequencies above the new
/// Nyquist limit; simple sample dropping aliases 48 kHz microphone input.
fn resample_16khz(input: &[f32], rate: u32) -> Vec<f32> {
    if rate == 16000 {
        return input
            .iter()
            .map(|x| {
                if x.is_finite() {
                    x.clamp(-1.0, 1.0)
                } else {
                    0.0
                }
            })
            .collect();
    }
    let count = (input.len() as u64 * 16000 / rate as u64) as usize;
    let cutoff = (16000.0 / rate as f64).min(1.0) * 0.94;
    let radius = (16.0 / cutoff).ceil() as isize;
    (0..count)
        .map(|i| {
            let position = i as f64 * rate as f64 / 16000.0;
            let center = position.floor() as isize;
            let (mut value, mut weight_sum) = (0.0, 0.0);
            for j in center - radius..=center + radius {
                if j < 0 || j as usize >= input.len() {
                    continue;
                }
                let distance = j as f64 - position;
                let phase = std::f64::consts::PI * distance * cutoff;
                let sinc = if phase.abs() < 1e-9 {
                    1.0
                } else {
                    phase.sin() / phase
                };
                let window =
                    0.5 + 0.5 * (std::f64::consts::PI * distance / (radius + 1) as f64).cos();
                let weight = sinc * window;
                let sample = input[j as usize];
                value += if sample.is_finite() {
                    sample as f64 * weight
                } else {
                    0.0
                };
                weight_sum += weight;
            }
            if weight_sum.abs() > 1e-12 {
                (value / weight_sum).clamp(-1.0, 1.0) as f32
            } else {
                0.0
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn speech_resampling_is_bounded_and_filters_aliasing() {
        let dc = resample_16khz(&vec![0.5; 4800], 48000);
        assert_eq!(dc.len(), 1600);
        assert!(dc.iter().all(|x| (*x - 0.5).abs() < 0.001));
        let high: Vec<_> = (0..4800)
            .map(|i| (i as f32 * 2.0 * std::f32::consts::PI * 12000.0 / 48000.0).sin())
            .collect();
        let out = resample_16khz(&high, 48000);
        assert!(out[100..1500].iter().all(|x| x.abs() < 0.01));
        assert_eq!(
            resample_16khz(&[f32::NAN, 5.0, -5.0], 16000),
            [0.0, 1.0, -1.0]
        );
    }
    #[test]
    fn downmix_preserves_silence_and_channels() {
        assert_eq!(mono(&[0i16, 0, 16384, -16384], 2), [0.0, 0.0]);
        assert_eq!(mono(&[1.0f32, 0.0, 0.25, 0.75], 2), [0.5, 0.5]);
        assert_eq!(mono(&[32768u16, 32768], 1), [0.0, 0.0]);
    }
    #[test]
    fn checksum_rejects_wrong_or_partial_files() {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(b"speech").unwrap();
        let digest = hex::encode(Sha256::digest(b"speech"));
        assert!(valid_file(file.path(), &digest, 6));
        assert!(!valid_file(file.path(), &digest, 5));
        assert!(!valid_file(file.path(), "bad", 6));
    }
    #[test]
    #[ignore = "Downloads the pinned model; uses a supplied WAV, never the microphone"]
    fn real_model_transcribes_fixture() {
        if std::env::var_os("LUNCHPAIL_SPEECH_TEST_GPU_OCR").is_some() {
            crate::translation::warm_gpu_ocr_for_speech_test().unwrap();
        }
        let (tx, _) = mpsc::channel();
        prepare(&AtomicU8::new(0), &tx).unwrap();
        let vocabulary: Vec<String> = std::env::var("LUNCHPAIL_SPEECH_TEST_VOCABULARY")
            .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default();
        let recognizer = recognizer_with_vocabulary(&vocabulary).unwrap();
        let file = std::env::var("LUNCHPAIL_SPEECH_TEST_WAV").expect("fixture path");
        let wave = sherpa_onnx::Wave::read(&file).unwrap();
        let stream = recognizer.create_stream();
        for chunk in wave.samples().chunks(3200) {
            stream.accept_waveform(wave.sample_rate(), chunk);
            while recognizer.is_ready(&stream) {
                recognizer.decode(&stream);
            }
        }
        stream.accept_waveform(
            wave.sample_rate(),
            &vec![0.0; wave.sample_rate() as usize / 2],
        );
        stream.input_finished();
        while recognizer.is_ready(&stream) {
            recognizer.decode(&stream);
        }
        let text = recognizer.get_result(&stream).unwrap().text.to_lowercase();
        let expected = std::env::var("LUNCHPAIL_SPEECH_EXPECT").expect("expected transcription");
        assert!(
            text.contains(&expected.to_lowercase()),
            "transcription: {text}"
        );
        eprintln!("Sherpa real-model transcription: {text}");
    }
}
