use anyhow::{Context, Result, ensure};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Engine {
    Llama,
    Whisper,
    Sherpa,
}

#[derive(Clone, Debug, Serialize)]
pub struct ModelFile {
    pub name: &'static str,
    pub bytes: u64,
    pub sha256: &'static str,
}

#[derive(Clone, Debug, Serialize)]
pub struct Model {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub engine: Engine,
    pub repository: &'static str,
    pub revision: &'static str,
    pub license: &'static str,
    pub files: &'static [ModelFile],
}

pub const MODELS: &[Model] = &[
    Model {
        id: "qwen35-08b",
        name: "Qwen3.5 0.8B · Compact · 834 MB",
        description: "Smallest assistant. Lower memory use, but less reliable reasoning than the larger models.",
        engine: Engine::Llama,
        repository: "ggml-org/Qwen3.5-0.8B-GGUF",
        revision: "8fea620810c4afa23dd6443f999a48574c1611a3",
        license: "Apache-2.0",
        files: &[ModelFile {
            name: "Qwen3.5-0.8B-Q8_0.gguf",
            bytes: 833592096,
            sha256: "37ae482d336108d23516fa35e8e0c4126688d81018b87178a18d752a1357814f",
        }],
    },
    Model {
        id: "qwen3-4b",
        name: "Qwen3 4B · Balanced · 2.50 GB",
        description: "Recommended starting point for game recommendations and catalog tools. Q4_K_M quantization.",
        engine: Engine::Llama,
        repository: "Qwen/Qwen3-4B-GGUF",
        revision: "bc640142c66e1fdd12af0bd68f40445458f3869b",
        license: "Apache-2.0",
        files: &[ModelFile {
            name: "Qwen3-4B-Q4_K_M.gguf",
            bytes: 2497280256,
            sha256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
        }],
    },
    Model {
        id: "qwen3-8b",
        name: "Qwen3 8B · Higher quality · 5.03 GB",
        description: "More capable, with higher RAM/VRAM requirements. Can be slow on a CPU. Q4_K_M quantization.",
        engine: Engine::Llama,
        repository: "Qwen/Qwen3-8B-GGUF",
        revision: "7c41481f57cb95916b40956ab2f0b139b296d974",
        license: "Apache-2.0",
        files: &[ModelFile {
            name: "Qwen3-8B-Q4_K_M.gguf",
            bytes: 5027783488,
            sha256: "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
        }],
    },
    Model {
        id: "whisper-tiny-en",
        name: "Whisper Tiny English · 78 MB",
        description: "Fast, low-memory speech recognition on CPU or GPU. English only.",
        engine: Engine::Whisper,
        repository: "ggerganov/whisper.cpp",
        revision: "5359861c739e955e79d9a303bcbc70fb988958b1",
        license: "MIT",
        files: &[ModelFile {
            name: "ggml-tiny.en.bin",
            bytes: 77704715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
        }],
    },
    Model {
        id: "whisper-base-en",
        name: "Whisper Base English · 148 MB",
        description: "Balanced speech recognition on CPU or GPU. English only.",
        engine: Engine::Whisper,
        repository: "ggerganov/whisper.cpp",
        revision: "5359861c739e955e79d9a303bcbc70fb988958b1",
        license: "MIT",
        files: &[ModelFile {
            name: "ggml-base.en.bin",
            bytes: 147964211,
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
        }],
    },
    Model {
        id: "whisper-small",
        name: "Whisper Small Multilingual · 488 MB",
        description: "Multilingual speech recognition with automatic language detection. CPU or GPU; slower on a CPU.",
        engine: Engine::Whisper,
        repository: "ggerganov/whisper.cpp",
        revision: "5359861c739e955e79d9a303bcbc70fb988958b1",
        license: "MIT",
        files: &[ModelFile {
            name: "ggml-small.bin",
            bytes: 487601967,
            sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
        }],
    },
    Model {
        id: "sherpa-zipformer-en",
        name: "Sherpa streaming English · 191 MB · CPU",
        description: "The existing low-latency streaming recognizer. Uses the CPU; choose Whisper for GPU acceleration.",
        engine: Engine::Sherpa,
        repository: "csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-21",
        revision: "9a65b6ea94c311ca770c2bf895b30f456a22d703",
        license: "Apache-2.0",
        files: &[
            ModelFile {
                name: "encoder-epoch-99-avg-1.int8.onnx",
                bytes: 187823992,
                sha256: "32c98281c7bd8b63e3e142d007251b37f120572e8fdea9a4f5a79ce22b10ec4f",
            },
            ModelFile {
                name: "decoder-epoch-99-avg-1.onnx",
                bytes: 2092566,
                sha256: "9da02b77cb08826756ec6a88635f35a40374e4164e7c6359121a9145958a6ceb",
            },
            ModelFile {
                name: "joiner-epoch-99-avg-1.int8.onnx",
                bytes: 259335,
                sha256: "831477d390e59a61f1b6a6f763b9903e6c6366ff6034f1ddba613be82637122f",
            },
            ModelFile {
                name: "tokens.txt",
                bytes: 5048,
                sha256: "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb",
            },
        ],
    },
];

pub fn find(id: &str) -> Result<&'static Model> {
    MODELS
        .iter()
        .find(|m| m.id == id)
        .context("Unknown local AI model")
}

pub fn directory(data: &Path, model: &Model) -> PathBuf {
    if model.engine == Engine::Sherpa {
        data.join("speech/zipformer-en-2023-06-21")
    } else {
        data.join("ai/models").join(model.id)
    }
}

pub fn bytes(model: &Model) -> u64 {
    model.files.iter().map(|f| f.bytes).sum()
}

pub fn installed(data: &Path, model: &Model) -> bool {
    model.files.iter().all(|f| {
        directory(data, model)
            .join(f.name)
            .metadata()
            .is_ok_and(|m| m.is_file() && m.len() == f.bytes)
    })
}

fn cancelled(cancel: &AtomicBool) -> Result<()> {
    ensure!(!cancel.load(Ordering::Relaxed), "Model operation cancelled");
    Ok(())
}

pub fn verify(data: &Path, model: &Model, cancel: &AtomicBool) -> Result<PathBuf> {
    for file in model.files {
        verify_file(&directory(data, model).join(file.name), file, cancel)?;
    }
    Ok(directory(data, model).join(model.files[0].name))
}

fn verify_file(path: &Path, file: &ModelFile, cancel: &AtomicBool) -> Result<()> {
    let mut source = fs::File::open(path).context("Model is not downloaded yet")?;
    ensure!(
        source.metadata()?.len() == file.bytes,
        "Model size mismatch; select it again to repair the download"
    );
    let mut hasher = Sha256::new();
    let mut buffer = vec![0_u8; 1024 * 1024];
    loop {
        cancelled(cancel)?;
        let count = source.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    ensure!(
        hex::encode(hasher.finalize()) == file.sha256,
        "Model checksum mismatch; select it again to repair the download"
    );
    Ok(())
}

/// Downloads only curated, immutable files. A cancelled transfer leaves a .part
/// file for resume; a bad hash is never promoted to an installed model.
pub fn download(
    data: &Path,
    model: &Model,
    cancel: &AtomicBool,
    mut progress: impl FnMut(u64, u64, &str),
) -> Result<()> {
    let dir = directory(data, model);
    fs::create_dir_all(&dir)?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(dir.join(".download.lock"))?;
    loop {
        cancelled(cancel)?;
        match fs2::FileExt::try_lock_exclusive(&lock) {
            Ok(()) => break,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50))
            }
            Err(e) => return Err(e).context("Locking model download"),
        }
    }
    let total = bytes(model);
    let mut complete = 0;
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(15)))
        .timeout_recv_body(Some(Duration::from_secs(15)))
        .http_status_as_error(false)
        .user_agent("Lunchpail integrated local AI model manager")
        .build()
        .into();
    for file in model.files {
        cancelled(cancel)?;
        let target = dir.join(file.name);
        progress(complete, total, "Verifying model files…");
        if verify_file(&target, file, cancel).is_ok() {
            complete += file.bytes;
            progress(complete, total, "Verified");
            continue;
        }
        cancelled(cancel)?;
        let partial = dir.join(format!("{}.part", file.name));
        let mut offset = partial.metadata().map(|m| m.len()).unwrap_or(0);
        // A full-sized, unverified partial may be left by interruption just
        // before promotion. Recheck it before deciding to redownload.
        if offset == file.bytes && verify_file(&partial, file, cancel).is_ok() {
            replace_verified(&partial, &target)?;
            complete += file.bytes;
            continue;
        }
        if offset >= file.bytes {
            offset = 0;
        }
        let url = format!(
            "https://huggingface.co/{}/resolve/{}/{}",
            model.repository, model.revision, file.name
        );
        let mut request = agent.get(&url);
        if offset > 0 {
            request = request.header("Range", format!("bytes={offset}-"));
        }
        let mut response = request.call().context("Downloading local AI model")?;
        if response.status().as_u16() == 206 {
            let range = response
                .headers()
                .get("content-range")
                .and_then(|h| h.to_str().ok())
                .unwrap_or("");
            ensure!(
                range.starts_with(&format!("bytes {offset}-"))
                    && range.ends_with(&format!("/{}", file.bytes)),
                "Unexpected model download range"
            );
        } else {
            ensure!(
                response.status().as_u16() == 200,
                "Model download returned HTTP {}",
                response.status()
            );
            offset = 0;
        }
        let mut output = fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(offset == 0)
            .append(offset > 0)
            .open(&partial)?;
        let mut reader = response.body_mut().as_reader();
        let mut buffer = [0_u8; 256 * 1024];
        let mut last_update = Instant::now() - Duration::from_secs(1);
        loop {
            cancelled(cancel)?;
            let count = reader.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            offset += count as u64;
            ensure!(
                offset <= file.bytes,
                "Model download exceeds its pinned size"
            );
            output.write_all(&buffer[..count])?;
            if last_update.elapsed() >= Duration::from_millis(80) {
                progress(complete + offset, total, file.name);
                last_update = Instant::now();
            }
        }
        output.sync_all()?;
        drop(output);
        progress(complete + offset, total, "Checking SHA-256…");
        verify_file(&partial, file, cancel)?;
        replace_verified(&partial, &target)?;
        complete += file.bytes;
    }
    progress(total, total, "Ready — model verified");
    Ok(())
}

fn replace_verified(source: &Path, target: &Path) -> Result<()> {
    // tempfile's persist replaces an existing corrupt file on Windows too.
    // Give it ownership of only our explicitly named .part file.
    let temporary = tempfile::TempPath::try_from_path(source)?;
    temporary
        .persist(target)
        .map_err(|e| e.error)
        .context("Installing verified model")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn catalog_is_pinned_and_has_no_path_traversal() {
        let mut ids = std::collections::HashSet::new();
        for model in MODELS {
            assert!(ids.insert(model.id));
            assert_eq!(model.revision.len(), 40);
            assert!(
                model
                    .id
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-')
            );
            for file in model.files {
                assert_eq!(file.sha256.len(), 64);
                assert!(file.bytes > 0);
                assert!(!file.name.contains(['/', '\\']));
                assert!(!file.name.starts_with('.'));
            }
        }
        assert!(find("../../outside").is_err());
    }
    #[test]
    fn verification_rejects_same_size_corruption_and_cancellation() {
        let dir = tempfile::tempdir().unwrap();
        let file = ModelFile {
            name: "test",
            bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        };
        let path = dir.path().join("test");
        fs::write(&path, b"abc").unwrap();
        assert!(verify_file(&path, &file, &AtomicBool::new(false)).is_ok());
        assert!(verify_file(&path, &file, &AtomicBool::new(true)).is_err());
        fs::write(&path, b"bad").unwrap();
        assert!(verify_file(&path, &file, &AtomicBool::new(false)).is_err());
    }
    #[test]
    fn sherpa_reuses_existing_user_model_directory() {
        assert_eq!(
            directory(Path::new("profile"), find("sherpa-zipformer-en").unwrap()),
            Path::new("profile/speech/zipformer-en-2023-06-21")
        );
    }
    #[test]
    #[ignore = "Downloads the pinned 78 MB Whisper model into a temporary profile"]
    fn live_download_cancels_resumes_and_verifies() {
        let profile = tempfile::tempdir().unwrap();
        let model = find("whisper-tiny-en").unwrap();
        let cancel = AtomicBool::new(false);
        let first = download(profile.path(), model, &cancel, |done, _, _| {
            if done > 1024 * 1024 {
                cancel.store(true, Ordering::Relaxed);
            }
        });
        assert!(first.is_err());
        assert!(!installed(profile.path(), model));
        let partial =
            directory(profile.path(), model).join(format!("{}.part", model.files[0].name));
        assert!(partial.metadata().unwrap().len() > 1024 * 1024);
        cancel.store(false, Ordering::Relaxed);
        download(profile.path(), model, &cancel, |done, total, detail| {
            if detail.contains("SHA") {
                eprintln!("{done}/{total}: {detail}");
            }
        })
        .unwrap();
        assert!(installed(profile.path(), model));
        assert!(verify(profile.path(), model, &cancel).is_ok());
        assert!(!partial.exists());
        // A second request verifies and reuses the installed model.
        download(profile.path(), model, &cancel, |_, _, _| {}).unwrap();
    }
}
