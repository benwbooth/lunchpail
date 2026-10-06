use super::{
    Message, Runtime, SYSTEM,
    settings::{self, Provider, Settings},
    tools,
};
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::time::Duration;

fn request(settings: &Settings, path: &str, body: Option<&Value>) -> Result<Value> {
    let profile = settings.profile();
    settings::validate_endpoint(&profile.endpoint)?;
    let endpoint = format!("{}{path}", profile.endpoint.trim_end_matches('/'));
    let key = settings::key(settings.provider)?;
    if matches!(settings.provider, Provider::Openai | Provider::Anthropic) {
        ensure!(key.is_some(), "Save an API key in assistant settings first");
    }
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .max_redirects(0)
        .timeout_global(Some(Duration::from_secs(90)))
        .build()
        .into();
    let mut response = if let Some(body) = body {
        let mut req = agent.post(&endpoint);
        if let Some(key) = &key {
            req = if settings.provider == Provider::Anthropic {
                req.header("x-api-key", key)
            } else {
                req.header("Authorization", format!("Bearer {key}"))
            };
        }
        if settings.provider == Provider::Anthropic {
            req = req.header("anthropic-version", "2023-06-01");
        }
        req.send_json(body)
    } else {
        let mut req = agent.get(&endpoint);
        if let Some(key) = &key {
            req = if settings.provider == Provider::Anthropic {
                req.header("x-api-key", key)
            } else {
                req.header("Authorization", format!("Bearer {key}"))
            };
        }
        if settings.provider == Provider::Anthropic {
            req = req.header("anthropic-version", "2023-06-01");
        }
        req.call()
    }
    .map_err(|e| match e {
        ureq::Error::StatusCode(code) => anyhow::anyhow!(
            "{} returned HTTP {code}. Check your model, sign-in/key and provider access.",
            settings.provider.label()
        ),
        _ => anyhow::anyhow!(
            "Could not reach {}. Check its server URL, network and running service.",
            settings.provider.label()
        ),
    })?;
    response
        .body_mut()
        .with_config()
        .limit(2 * 1024 * 1024)
        .read_json()
        .context("Provider returned invalid or oversized JSON")
}
pub fn models(settings: &Settings) -> Result<Value> {
    ensure!(
        !matches!(
            settings.provider,
            Provider::Builtin | Provider::Codex | Provider::ClaudeCode
        ),
        "This provider uses its locally configured model; enter an optional model override or leave it blank"
    );
    let value = request(
        settings,
        if settings.provider == Provider::Ollama {
            "/api/tags"
        } else {
            "/models"
        },
        None,
    )?;
    let rows = if settings.provider == Provider::Ollama {
        &value["models"]
    } else {
        &value["data"]
    };
    let mut names: Vec<String> = rows
        .as_array()
        .context("Model list is missing")?
        .iter()
        .filter_map(|r| {
            r[if settings.provider == Provider::Ollama {
                "name"
            } else {
                "id"
            }]
            .as_str()
            .map(str::to_owned)
        })
        .collect();
    names.sort();
    names.dedup();
    Ok(json!(names))
}
fn definitions(provider: Provider) -> Vec<Value> {
    tools::definitions().into_iter().map(|t| match provider {
        Provider::Anthropic => json!({"name":t.name,"description":t.description,"input_schema":t.input_schema}),
        Provider::Openai => json!({"type":"function","name":t.name,"description":t.description,"parameters":t.input_schema,"strict":false}),
        _ => json!({"type":"function","function":{"name":t.name,"description":t.description,"parameters":t.input_schema}}),
    }).collect()
}
pub fn conversation(
    settings: &Settings,
    history: &[Message],
    runtime: &mut Runtime<'_>,
) -> Result<String> {
    conversation_with(settings, history, runtime, |path, body| {
        request(settings, path, Some(body))
    })
}
fn conversation_with(
    settings: &Settings,
    history: &[Message],
    runtime: &mut Runtime<'_>,
    mut send: impl FnMut(&str, &Value) -> Result<Value>,
) -> Result<String> {
    let model = settings.profile().model;
    ensure!(
        !model.trim().is_empty(),
        "Choose a model in assistant settings (Refresh models lists available models)"
    );
    let provider = settings.provider;
    let mut messages: Vec<Value> = history
        .iter()
        .map(|m| json!({"role":m.role,"content":m.content}))
        .collect();
    if !matches!(provider, Provider::Openai | Provider::Anthropic) {
        messages.insert(0, json!({"role":"system","content":SYSTEM}));
    }
    let defs = definitions(provider);
    for _ in 0..16 {
        runtime.check()?;
        let (path, body) = match provider {
            Provider::Openai => (
                "/responses",
                json!({"model":model,"instructions":SYSTEM,"input":messages,"tools":defs,"store":false,"max_output_tokens":2200}),
            ),
            Provider::Anthropic => (
                "/messages",
                json!({"model":model,"system":SYSTEM,"messages":messages,"tools":defs,"max_tokens":2200}),
            ),
            Provider::Ollama => (
                "/api/chat",
                json!({"model":model,"messages":messages,"tools":defs,"stream":false,"think":false,"options":{"num_predict":1400}}),
            ),
            _ => (
                "/chat/completions",
                json!({"model":model,"messages":messages,"tools":defs,"stream":false}),
            ),
        };
        let response = send(path, &body)?;
        runtime.check()?;
        match provider {
            Provider::Openai => {
                let output = response["output"]
                    .as_array()
                    .context("Provider returned no output")?;
                // Preserve reasoning items and provider call IDs exactly, as required by Responses.
                messages.extend(output.iter().cloned());
                let mut called = false;
                let mut text = Vec::new();
                for item in output {
                    if item["type"] == "function_call" {
                        called = true;
                        let name = item["name"].as_str().unwrap_or("");
                        let args =
                            serde_json::from_str(item["arguments"].as_str().unwrap_or("{}"))?;
                        let result = runtime.invoke(name, args);
                        messages.push(json!({"type":"function_call_output","call_id":item["call_id"],"output":result.to_string()}));
                    } else if let Some(content) = item["content"].as_array() {
                        for c in content {
                            if let Some(t) = c["text"].as_str() {
                                text.push(t.to_owned());
                            }
                        }
                    }
                }
                if !called {
                    return Ok(text.join("\n"));
                }
            }
            Provider::Anthropic => {
                let content = response["content"]
                    .as_array()
                    .context("Provider returned no content")?;
                messages.push(json!({"role":"assistant","content":content}));
                let mut results = Vec::new();
                let mut text = Vec::new();
                for item in content {
                    if item["type"] == "tool_use" {
                        let result = runtime
                            .invoke(item["name"].as_str().unwrap_or(""), item["input"].clone());
                        results.push(json!({"type":"tool_result","tool_use_id":item["id"],"content":result.to_string(),"is_error":result.get("error").is_some()}));
                    } else if let Some(t) = item["text"].as_str() {
                        text.push(t.to_owned());
                    }
                }
                if results.is_empty() {
                    return Ok(text.join("\n"));
                }
                messages.push(json!({"role":"user","content":results}));
            }
            _ => {
                let message = if provider == Provider::Ollama {
                    &response["message"]
                } else {
                    &response["choices"][0]["message"]
                };
                ensure!(
                    message.is_object(),
                    "Provider returned no assistant message"
                );
                messages.push(message.clone());
                let calls = message["tool_calls"].as_array().filter(|a| !a.is_empty());
                let Some(calls) = calls else {
                    return Ok(message["content"].as_str().unwrap_or("").into());
                };
                for call in calls {
                    let name = call["function"]["name"].as_str().unwrap_or("");
                    let args = &call["function"]["arguments"];
                    let args = if let Some(text) = args.as_str() {
                        serde_json::from_str(text)?
                    } else {
                        args.clone()
                    };
                    let result = runtime.invoke(name, args);
                    messages.push(if provider == Provider::Ollama {
                        json!({"role":"tool","tool_name":name,"content":result.to_string()})
                    } else { json!({"role":"tool","tool_call_id":call["id"],"content":result.to_string()}) });
                }
            }
        }
    }
    anyhow::bail!("Provider reached the tool limit. Try a more specific request.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{atomic::AtomicBool, mpsc};
    #[test]
    fn ollama_properties_use_object_schemas_not_boolean_shortcuts() {
        for tool in definitions(Provider::Ollama) {
            if let Some(properties) = tool["function"]["parameters"]["properties"].as_object() {
                for (name, schema) in properties {
                    assert!(
                        schema.is_object(),
                        "{}.{name}: {schema}",
                        tool["function"]["name"]
                    );
                }
            }
        }
    }
    #[test]
    fn all_http_protocols_round_trip_real_tool_results_and_keep_provider_ids() {
        for provider in [
            Provider::Ollama,
            Provider::Openai,
            Provider::Anthropic,
            Provider::Compatible,
        ] {
            let mut settings = Settings {
                provider,
                ..Settings::default()
            };
            let mut profile = settings.profile();
            profile.model = "fixture-model".into();
            settings.profiles.insert(provider.key().into(), profile);
            let (tx, rx) = mpsc::channel();
            let handler = std::thread::spawn(move || {
                while let Ok(event) = rx.recv() {
                    if let super::super::Event::Tool {
                        name,
                        arguments,
                        reply,
                        ..
                    } = event
                    {
                        assert_eq!(name, "get_context");
                        assert_eq!(arguments, json!({}));
                        reply.send(json!({"selected_game":{"id":"fixture","title":"Fixture Game"},"game_running":false})).unwrap();
                        return;
                    }
                }
                panic!("Tool request never arrived");
            });
            let cancel = AtomicBool::new(false);
            let mut runtime = Runtime::new(&cancel, &tx);
            let history = vec![Message {
                role: "user".into(),
                content: "What is selected?".into(),
            }];
            let mut step = 0;
            let reply = conversation_with(&settings, &history, &mut runtime, |path, body| {
                step += 1;
                assert_eq!(body["model"], "fixture-model");
                assert!(body["tools"].as_array().unwrap().len() >= 21);
                if step == 1 {
                    Ok(match provider {
                        Provider::Openai => {
                            assert_eq!(path, "/responses"); assert_eq!(body["store"], false);
                            json!({"output":[{"type":"reasoning","id":"reason-id","summary":[]},{"type":"function_call","call_id":"call-7","name":"get_context","arguments":"{}"}]})
                        }
                        Provider::Anthropic => json!({"content":[{"type":"tool_use","id":"call-7","name":"get_context","input":{}}]}),
                        Provider::Ollama => json!({"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"get_context","arguments":{}}}]}}),
                        _ => json!({"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-7","type":"function","function":{"name":"get_context","arguments":"{}"}}]}}]}),
                    })
                } else {
                    assert_eq!(step, 2);
                    match provider {
                        Provider::Openai => {
                            assert_eq!(body["input"][1]["id"], "reason-id");
                            assert_eq!(body["input"][3]["call_id"], "call-7");
                            assert!(body["input"][3]["output"].as_str().unwrap().contains("Fixture Game"));
                            Ok(json!({"output":[{"type":"message","content":[{"type":"output_text","text":"Fixture Game is selected."}]}]}))
                        }
                        Provider::Anthropic => {
                            assert_eq!(body["messages"][2]["content"][0]["tool_use_id"], "call-7");
                            assert_eq!(body["messages"][2]["content"][0]["is_error"], false);
                            Ok(json!({"content":[{"type":"text","text":"Fixture Game is selected."}]}))
                        }
                        Provider::Ollama => {
                            assert_eq!(body["messages"][3]["tool_name"], "get_context");
                            Ok(json!({"message":{"role":"assistant","content":"Fixture Game is selected."}}))
                        }
                        _ => {
                            assert_eq!(body["messages"][3]["tool_call_id"], "call-7");
                            Ok(json!({"choices":[{"message":{"role":"assistant","content":"Fixture Game is selected."}}]}))
                        }
                    }
                }
            }).unwrap();
            assert_eq!(reply, "Fixture Game is selected.");
            handler.join().unwrap();
        }
    }
    #[test]
    fn cancelled_requests_never_enter_provider_transport_or_dispatch_tools() {
        let settings = Settings {
            provider: Provider::Ollama,
            profiles: [(
                "ollama".into(),
                settings::Profile {
                    model: "fixture".into(),
                    endpoint: "http://127.0.0.1:11434".into(),
                    executable: String::new(),
                },
            )]
            .into(),
            ..Settings::default()
        };
        let (tx, _rx) = mpsc::channel();
        let cancel = AtomicBool::new(true);
        let result = conversation_with(&settings, &[], &mut Runtime::new(&cancel, &tx), |_, _| {
            panic!("Cancelled provider call")
        });
        assert!(result.is_err());
    }
}
