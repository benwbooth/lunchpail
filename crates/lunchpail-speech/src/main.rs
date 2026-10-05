use anyhow::{Context, Result, bail, ensure};
use lunchpail_ai::{Device, Reply, Request};
use std::{
    ffi::CStr,
    io::Write,
    sync::atomic::{AtomicBool, Ordering},
};
use whisper_rs::{
    FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters, whisper_rs_sys as sys,
};

const GPU_BUILD: bool = cfg!(any(feature = "vulkan", feature = "metal"));
static GPU_USED: AtomicBool = AtomicBool::new(false);

unsafe extern "C" fn native_log(
    _level: sys::ggml_log_level,
    text: *const std::ffi::c_char,
    _data: *mut std::ffi::c_void,
) {
    if text.is_null() {
        return;
    }
    // whisper.cpp owns the callback string for this call.
    let text = unsafe { CStr::from_ptr(text) }.to_string_lossy();
    if text.contains("whisper_backend_init_gpu: using ") {
        GPU_USED.store(true, Ordering::Relaxed);
    }
    if text.contains("whisper_backend_init_gpu: failed to initialize") {
        GPU_USED.store(false, Ordering::Relaxed);
    }
    let _ = std::io::stderr().write_all(text.as_bytes());
}

fn devices() -> Vec<Device> {
    if !GPU_BUILD {
        return Vec::new();
    }
    // The registry is process-local. Whisper's gpu_device is an index among
    // GPUs (unlike llama.cpp's index among all backend devices).
    unsafe {
        sys::ggml_backend_load_all();
        (0..sys::ggml_backend_dev_count())
            .filter_map(|index| {
                let device = sys::ggml_backend_dev_get(index);
                let kind = sys::ggml_backend_dev_type(device);
                if kind != sys::ggml_backend_dev_type_GGML_BACKEND_DEVICE_TYPE_GPU
                    && kind != sys::ggml_backend_dev_type_GGML_BACKEND_DEVICE_TYPE_IGPU
                {
                    return None;
                }
                let name = CStr::from_ptr(sys::ggml_backend_dev_description(device))
                    .to_string_lossy()
                    .into_owned();
                let backend = CStr::from_ptr(sys::ggml_backend_dev_name(device))
                    .to_string_lossy()
                    .into_owned();
                let (mut free, mut total) = (0, 0);
                sys::ggml_backend_dev_memory(device, &mut free, &mut total);
                Some((
                    name,
                    backend,
                    free,
                    total,
                    kind == sys::ggml_backend_dev_type_GGML_BACKEND_DEVICE_TYPE_IGPU,
                ))
            })
            .enumerate()
            .map(|(id, (name, backend, free, total, integrated))| Device {
                id,
                name,
                backend,
                memory_bytes: total as u64,
                free_bytes: free as u64,
                integrated,
            })
            .collect()
    }
}

fn main() -> Result<()> {
    unsafe {
        sys::whisper_log_set(Some(native_log), std::ptr::null_mut());
    }
    lunchpail_ai::serve(|request| match request {
        Request::Probe => Ok(Reply {
            devices: devices(),
            ..Reply::success(
                String::new(),
                if GPU_BUILD { "GPU runtime" } else { "CPU" }.into(),
            )
        }),
        Request::Transcribe {
            model,
            device,
            samples,
            language,
        } => {
            ensure!(
                (1600..=240000).contains(&samples.len()),
                "Speech input must be 0.1–15 seconds of mono 16 kHz audio"
            );
            ensure!(
                samples.iter().all(|s| s.is_finite() && s.abs() <= 1.01),
                "Invalid microphone samples"
            );
            ensure!(
                matches!(language.as_str(), "en" | "auto"),
                "Unsupported speech language preference"
            );
            let available = devices();
            let selected = if GPU_BUILD {
                Some(
                    match device {
                        Some(id) => available.iter().find(|d| d.id == id),
                        None => available
                            .iter()
                            .max_by_key(|d| (!d.integrated, d.free_bytes)),
                    }
                    .context("No compatible GPU found by the bundled speech runtime")?,
                )
            } else {
                None
            };
            let mut context_params = WhisperContextParameters::default();
            context_params.use_gpu(selected.is_some());
            if let Some(gpu) = selected {
                context_params.gpu_device(gpu.id as i32);
            }
            GPU_USED.store(false, Ordering::Relaxed);
            let context = WhisperContext::new_with_params(&model, context_params)
                .context("Loading selected speech model")?;
            let mut state = context.create_state()?;
            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
            params.set_n_threads(
                std::thread::available_parallelism()
                    .map(|n| n.get())
                    .unwrap_or(2)
                    .clamp(1, 8) as i32,
            );
            params.set_language(if language == "auto" { None } else { Some("en") });
            params.set_translate(false);
            params.set_no_context(true);
            params.set_print_special(false);
            params.set_print_progress(false);
            params.set_print_realtime(false);
            params.set_print_timestamps(false);
            state
                .full(params, &samples)
                .context("Transcribing microphone audio")?;
            let text = state
                .as_iter()
                .map(|s| s.to_string())
                .collect::<Vec<_>>()
                .join("");
            let label = if let Some(gpu) = selected {
                ensure!(
                    GPU_USED.load(Ordering::Relaxed),
                    "Speech model did not initialize a GPU backend"
                );
                format!("{} · {}", gpu.name, gpu.backend)
            } else {
                "CPU".into()
            };
            Ok(Reply::success(text.trim().to_owned(), label))
        }
        _ => bail!("This worker only supports speech inference"),
    })
}
