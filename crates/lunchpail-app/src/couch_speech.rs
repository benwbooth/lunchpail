//! Local, opt-in streaming search. Audio is never saved or sent over the network.
use anyhow::{Context, Result, bail, ensure};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use sha2::{Digest, Sha256};
use sherpa_onnx::{OnlineRecognizer, OnlineRecognizerConfig};
use std::{
    io::{Read, Write},
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
const REVISION: &str = "9a65b6ea94c311ca770c2bf895b30f456a22d703";
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
    Text(String),
    Finished(String),
    Error(String, bool),
}

pub fn model_dir() -> Result<PathBuf> {
    Ok(crate::app_paths::project_dirs()
        .context("Application data directory unavailable")?
        .data_local_dir()
        .join("speech/zipformer-en-2023-06-21"))
}

pub fn installed() -> bool {
    model_dir().is_ok_and(|dir| {
        FILES.iter().all(|(name, _, size)| {
            dir.join(name)
                .metadata()
                .is_ok_and(|meta| meta.len() == *size)
        })
    })
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
    model_dir().is_ok_and(|dir| {
        FILES
            .iter()
            .all(|(name, digest, size)| valid_file(&dir.join(name), digest, *size))
    })
}

pub fn prepare(control: &AtomicU8, tx: &mpsc::Sender<Event>) -> Result<()> {
    let dir = model_dir()?;
    std::fs::create_dir_all(&dir)?;
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_body(Some(Duration::from_secs(10)))
        .timeout_global(Some(Duration::from_secs(300)))
        .user_agent("Lunchpail local voice search model setup")
        .build()
        .into();
    for (name, digest, size) in FILES {
        ensure!(control.load(Ordering::Relaxed) == 0, "Setup cancelled");
        let path = dir.join(name);
        if valid_file(&path, digest, size) {
            continue;
        }
        let _ = tx.send(Event::Status(format!(
            "Downloading {name} (one-time English model, 191 MB)…"
        )));
        let url = format!(
            "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-21/resolve/{REVISION}/{name}"
        );
        let mut response = agent.get(&url).call()?;
        let mut reader = response.body_mut().as_reader();
        let mut temporary = tempfile::NamedTempFile::new_in(&dir)?;
        let mut hash = Sha256::new();
        let mut buffer = [0u8; 65536];
        let mut received = 0u64;
        loop {
            ensure!(control.load(Ordering::Relaxed) == 0, "Setup cancelled");
            let count = reader.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            received += count as u64;
            ensure!(received <= size, "Speech model exceeds expected size");
            hash.update(&buffer[..count]);
            temporary.write_all(&buffer[..count])?;
        }
        ensure!(
            received == size && hex::encode(hash.finalize()) == digest,
            "Speech model checksum mismatch: {name}"
        );
        temporary.as_file().sync_all()?;
        temporary.persist(&path).map_err(|error| error.error)?;
    }
    Ok(())
}

fn recognizer() -> Result<OnlineRecognizer> {
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
    config.enable_endpoint = true;
    config.rule1_min_trailing_silence = 4.0;
    config.rule2_min_trailing_silence = 1.2;
    config.rule3_min_utterance_length = 15.0;
    OnlineRecognizer::create(&config).context("Could not load the local speech recognizer")
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
    let recognizer = recognizer()?;
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

#[cfg(test)]
mod tests {
    use super::*;
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
        let recognizer = recognizer().unwrap();
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
