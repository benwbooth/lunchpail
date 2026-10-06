use anyhow::{Context, Result, bail, ensure};
use llama_cpp_2::{
    context::params::LlamaContextParams,
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{LlamaChatMessage, LlamaChatTemplate, LlamaModel, params::LlamaModelParams},
    sampling::LlamaSampler,
};
use lunchpail_ai::{ChatMessage, Device, Reply, Request};
use std::{
    ffi::CStr,
    io::Write,
    num::NonZeroU32,
    path::PathBuf,
    sync::atomic::{AtomicU32, Ordering},
};

const GPU_BUILD: bool = cfg!(any(feature = "vulkan", feature = "metal"));
static OFFLOADED: AtomicU32 = AtomicU32::new(0);

unsafe extern "C" fn native_log(
    _level: llama_cpp_sys_2::ggml_log_level,
    text: *const std::ffi::c_char,
    _data: *mut std::ffi::c_void,
) {
    if text.is_null() {
        return;
    }
    // llama.cpp owns the valid, NUL-terminated message for this callback.
    let text = unsafe { CStr::from_ptr(text) }.to_string_lossy();
    if let Some(count) = text
        .split("offloaded ")
        .nth(1)
        .and_then(|s| s.split('/').next())
        .and_then(|s| s.parse::<u32>().ok())
    {
        OFFLOADED.store(count, Ordering::Relaxed);
    }
    let _ = std::io::stderr().write_all(text.as_bytes());
}

fn devices() -> Vec<Device> {
    if !GPU_BUILD {
        return Vec::new();
    }
    llama_cpp_2::list_llama_ggml_backend_devices()
        .into_iter()
        .filter(|d| {
            matches!(
                d.device_type,
                llama_cpp_2::LlamaBackendDeviceType::Gpu
                    | llama_cpp_2::LlamaBackendDeviceType::IntegratedGpu
            )
        })
        .map(|d| Device {
            id: d.index,
            name: d.description,
            backend: d.backend,
            memory_bytes: d.memory_total as u64,
            free_bytes: d.memory_free as u64,
            integrated: d.device_type == llama_cpp_2::LlamaBackendDeviceType::IntegratedGpu,
        })
        .collect()
}

fn generate(
    backend: &LlamaBackend,
    model: &LlamaModel,
    system: String,
    prompt: String,
    messages: Vec<ChatMessage>,
    schema: serde_json::Value,
    max_tokens: u32,
) -> Result<String> {
    ensure!(
        system.len() <= 32000 && prompt.len() <= 96000
            && messages.len() <= 64 && messages.iter().map(|m| m.content.len()).sum::<usize>() <= 96000,
        "Assistant prompt is too large"
    );
    let clean = |s: String| s.replace("<|", "< |").replace('\0', "");
    // The curated Qwen models share ChatML. Explicitly end the thinking span
    // so constrained tool JSON starts immediately, including on CPU models.
    let mut chat = vec![LlamaChatMessage::new("system".into(), clean(system))?];
    if messages.is_empty() {
        chat.push(LlamaChatMessage::new("user".into(), format!("{}\n/no_think", clean(prompt)))?);
    } else {
        ensure!(prompt.is_empty(), "Use either a prompt or structured messages, not both");
        for message in messages {
            ensure!(matches!(message.role.as_str(), "user" | "assistant" | "tool"), "Unsupported conversation role");
            chat.push(LlamaChatMessage::new(message.role, clean(message.content))?);
        }
    }
    let mut formatted =
        model.apply_chat_template(&LlamaChatTemplate::new("chatml")?, &chat, true)?;
    formatted.push_str("<think>\n\n</think>\n\n");
    let tokens = model.vocab().tokenize(formatted.as_bytes(), true, true);
    let limit = max_tokens.clamp(32, 1500) as usize;
    ensure!(
        tokens.len() + limit < 8192,
        "Assistant context is full. Start a new question."
    );
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(2)
        .clamp(1, 8) as i32;
    let params = LlamaContextParams::default()
        .with_n_ctx(NonZeroU32::new(8192))
        .with_n_batch(512)
        .with_n_ubatch(512)
        .with_n_threads(threads)
        .with_n_threads_batch(threads);
    let mut context = model
        .new_context(backend, params)
        .context("Allocating assistant context")?;
    let mut batch = LlamaBatch::new(512, 1);
    for (chunk_index, chunk) in tokens.chunks(512).enumerate() {
        batch.clear();
        for (i, &token) in chunk.iter().enumerate() {
            let position = chunk_index * 512 + i;
            batch.add(token, position as i32, &[0], position + 1 == tokens.len())?;
        }
        context.decode(&mut batch)?;
    }
    let grammar = llama_cpp_2::json_schema_to_grammar(&schema.to_string())?;
    let mut sampler = LlamaSampler::chain_simple([
        LlamaSampler::grammar(model, &grammar, "root")?,
        LlamaSampler::greedy(),
    ]);
    let mut result = Vec::new();
    for position in tokens.len()..tokens.len() + limit {
        let token = sampler.sample(&context, batch.n_tokens() - 1);
        // sample() already accepts the token. Accepting it a second time
        // corrupts grammar state and can abort the native runtime.
        if model.vocab().is_eog(token) {
            let text = String::from_utf8(result).context("Assistant returned invalid text")?;
            serde_json::from_str::<serde_json::Value>(&text)
                .context("Assistant returned incomplete JSON")?;
            return Ok(text);
        }
        result.extend(model.vocab().token_to_piece(token, true, None));
        batch.clear();
        batch.add(token, position as i32, &[0], true)?;
        context.decode(&mut batch)?;
    }
    bail!("Assistant response exceeded its token limit. Try a simpler question or a larger model.")
}

fn main() -> Result<()> {
    // Keep stdout a clean JSON-lines transport and retain proof of actual
    // layer offload, rather than reporting the requested backend as success.
    unsafe {
        llama_cpp_sys_2::llama_log_set(Some(native_log), std::ptr::null_mut());
    }
    let backend = LlamaBackend::init()?;
    let mut loaded: Option<(PathBuf, Option<usize>, LlamaModel, String)> = None;
    lunchpail_ai::serve(|request| match request {
        Request::Probe => Ok(Reply {
            devices: devices(),
            ..Reply::success(
                String::new(),
                if GPU_BUILD { "GPU runtime" } else { "CPU" }.into(),
            )
        }),
        Request::Generate {
            model,
            device,
            system,
            prompt,
            messages,
            schema,
            max_tokens,
        } => {
            let available = devices();
            let selected = if GPU_BUILD {
                let gpu = match device {
                    Some(index) => available.iter().find(|d| d.id == index),
                    None => available
                        .iter()
                        .max_by_key(|d| (!d.integrated, d.free_bytes)),
                }
                .context("No compatible GPU found by the bundled runtime")?;
                Some(gpu)
            } else {
                None
            };
            let selected_id = selected.map(|d| d.id);
            if loaded
                .as_ref()
                .is_none_or(|(path, id, _, _)| path != &model || *id != selected_id)
            {
                loaded = None; // Release the previous model before allocating another.
                OFFLOADED.store(0, Ordering::Relaxed);
                let mut params = LlamaModelParams::default().with_n_gpu_layers(0);
                if let Some(gpu) = selected {
                    params = params.with_n_gpu_layers(1000).with_devices(&[gpu.id])?;
                }
                let new_model = LlamaModel::load_from_file(&backend, &model, &params)
                    .context("Loading selected assistant model")?;
                let label = if let Some(gpu) = selected {
                    let layers = OFFLOADED.load(Ordering::Relaxed);
                    ensure!(
                        layers > 0,
                        "The GPU runtime loaded the model without offloading any layers"
                    );
                    format!("{} · {} · {layers} layers offloaded", gpu.name, gpu.backend)
                } else {
                    "CPU".into()
                };
                loaded = Some((model, selected_id, new_model, label));
            }
            let (_, _, model, device) = loaded.as_ref().context("Assistant model did not load")?;
            let text = generate(&backend, model, system, prompt, messages, schema, max_tokens)?;
            Ok(Reply::success(text, device.clone()))
        }
        _ => bail!("This worker only supports assistant inference"),
    })
}
