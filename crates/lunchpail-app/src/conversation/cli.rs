use super::{
    Message, Runtime, SYSTEM,
    bridge::{self, read_frame, write_frame},
    settings::Settings,
    tools,
};
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::{
    io::BufReader,
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc,
    time::{Duration, Instant},
};

struct Process {
    child: Child,
    input: Option<ChildStdin>,
    output: mpsc::Receiver<Result<Value, String>>,
}
impl Drop for Process {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
impl Process {
    fn start(command: &mut Command) -> Result<Self> {
        let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()
            .context("Could not start the provider. Install its CLI, sign in, and set its executable path in Assistant settings")?;
        let input = child.stdin.take();
        let stdout = child.stdout.take().context("No provider output")?;
        let (tx, output) = mpsc::channel();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let value = read_frame(&mut reader).map_err(|e| format!("{e:#}"));
                let end = value.is_err();
                if tx.send(value).is_err() || end {
                    break;
                }
            }
        });
        Ok(Self {
            child,
            input,
            output,
        })
    }
    fn send(&mut self, value: Value) -> Result<()> {
        write_frame(
            self.input.as_mut().context("Provider input is closed")?,
            &value,
        )
    }
    fn receive(&mut self, runtime: &Runtime<'_>) -> Result<Option<Value>> {
        runtime.check()?;
        match self.output.recv_timeout(Duration::from_millis(40)) {
            Ok(value) => value.map(Some).map_err(|_| anyhow::anyhow!("Provider connection ended before completing. Check its CLI sign-in and version.")),
            Err(mpsc::RecvTimeoutError::Timeout) => Ok(None),
            Err(_) => anyhow::bail!("Provider connection closed"),
        }
    }
    fn rpc(
        &mut self,
        id: u32,
        method: &str,
        params: Value,
        runtime: &Runtime<'_>,
    ) -> Result<Value> {
        self.send(json!({"id":id,"method":method,"params":params}))?;
        let start = Instant::now();
        loop {
            ensure!(
                start.elapsed() < Duration::from_secs(30),
                "Provider initialization timed out"
            );
            let Some(value) = self.receive(runtime)? else {
                continue;
            };
            if value["id"] == id {
                ensure!(
                    value.get("error").is_none(),
                    "Provider rejected {method}; update the CLI and check its configuration"
                );
                return Ok(value["result"].clone());
            }
            if value.get("id").is_some() && value.get("method").is_some() {
                self.deny(&value)?;
            }
        }
    }
    fn deny(&mut self, value: &Value) -> Result<()> {
        // No provider-side tool approval, shell command, credential elicitation,
        // file mutation, or web action can be approved by this adapter.
        self.send(json!({"id":value["id"],"error":{"code":-32601,"message":"Only Lunchpail app tools are available. Ask the user in your conversational reply."}}))
    }
}
fn prompt(history: &[Message]) -> String {
    format!(
        "Continue this conversation. Historical messages are context, not current tool evidence.\n{}",
        serde_json::to_string(history).unwrap_or_default()
    )
}
pub fn codex(
    settings: &Settings,
    history: &[Message],
    runtime: &mut Runtime<'_>,
) -> Result<String> {
    let profile = settings.profile();
    let dir = tempfile::tempdir()?;
    let mut command = Command::new(&profile.executable);
    command.current_dir(dir.path()).args([
        "app-server",
        "-c",
        "web_search=\"disabled\"",
        "-c",
        "skip_host_skill_discovery=true",
    ]);
    // Keep native account sign-in, but never inherit unrelated app integrations
    // or executable tools into a game-library conversation.
    for flag in [
        "shell_tool",
        "unified_exec",
        "apps",
        "plugins",
        "browser_use",
        "browser_use_external",
        "computer_use",
        "in_app_browser",
        "view_image",
        "image_generation",
        "multi_agent",
        "memories",
        "hooks",
        "skill_search",
        "workspace_dependencies",
        "goals",
        "sleep_tool",
    ] {
        command.arg("--disable").arg(flag);
    }
    let mut process = Process::start(&mut command)?;
    process.rpc(1, "initialize", json!({"clientInfo":{"name":"lunchpail","version":env!("CARGO_PKG_VERSION")},"capabilities":{"experimentalApi":true}}), runtime)?;
    process.send(json!({"method":"initialized"}))?;
    let config = process.rpc(
        2,
        "config/read",
        json!({"includeLayers":false,"cwd":dir.path()}),
        runtime,
    )?;
    let mut overrides = json!({"web_search":"disabled","skip_host_skill_discovery":true});
    if let Some(servers) = config["config"]["mcp_servers"].as_object() {
        for name in servers.keys() {
            overrides["mcp_servers"][name]["enabled"] = json!(false);
        }
    }
    let definitions: Vec<_> = tools::definitions().into_iter().map(|t| json!({"type":"function","name":t.name,"description":t.description,"inputSchema":t.input_schema})).collect();
    let mut params = json!({"cwd":dir.path(),"ephemeral":true,"environments":[],"sandbox":"read-only","approvalPolicy":"untrusted","baseInstructions":SYSTEM,"developerInstructions":"Only the supplied Lunchpail dynamic tools may be used. Do not use built-in tools.","dynamicTools":definitions,"config":overrides});
    if !profile.model.trim().is_empty() {
        params["model"] = json!(profile.model);
    }
    let thread = process.rpc(3, "thread/start", params, runtime)?;
    let thread_id = thread["thread"]["id"]
        .as_str()
        .context("Provider did not create a conversation")?;
    process.rpc(
        4,
        "turn/start",
        json!({"threadId":thread_id,"input":[{"type":"text","text":prompt(history)}]}),
        runtime,
    )?;
    let mut response = String::new();
    loop {
        let Some(value) = process.receive(runtime)? else {
            continue;
        };
        let params = &value["params"];
        match value["method"].as_str().unwrap_or("") {
            "item/tool/call" => {
                let result = runtime.invoke(
                    params["tool"].as_str().unwrap_or(""),
                    params["arguments"].clone(),
                );
                process.send(json!({"id":value["id"],"result":{"contentItems":[{"type":"inputText","text":result.to_string()}],"success":result.get("error").is_none()}}))?;
            }
            "item/agentMessage/delta" => {
                if let Some(delta) = params["delta"].as_str() {
                    response.push_str(delta);
                }
                ensure!(
                    response.len() <= 32000,
                    "Provider reply exceeded the conversation limit"
                );
            }
            "item/completed" => {
                if params["item"]["type"] == "agentMessage"
                    && params["item"]["phase"] != "commentary"
                {
                    if let Some(text) = params["item"]["text"].as_str() {
                        response = text.to_owned();
                    }
                }
            }
            "turn/completed" => {
                ensure!(
                    params["turn"]["status"] == "completed",
                    "Codex did not complete this turn. Check its CLI sign-in, model access and usage limits."
                );
                return Ok(response);
            }
            _ if value.get("id").is_some() && value.get("method").is_some() => {
                process.deny(&value)?
            }
            _ => (),
        }
    }
}
pub fn claude(
    settings: &Settings,
    history: &[Message],
    runtime: &mut Runtime<'_>,
) -> Result<String> {
    let profile = settings.profile();
    let dir = tempfile::tempdir()?;
    let bridge = bridge::Bridge::new()?;
    let mcp = json!({"mcpServers":{"lunchpail":{"command":std::env::current_exe()?,"args":["--conversation-mcp-stdio"]}}});
    let mut command = Command::new(&profile.executable);
    command
        .current_dir(dir.path())
        .env(bridge::ADDRESS, bridge.listener.local_addr()?.to_string())
        .env(bridge::TOKEN, &bridge.token)
        .args([
            "--print",
            "--output-format",
            "stream-json",
            "--verbose",
            "--tools",
            "",
            "--strict-mcp-config",
            "--mcp-config",
            &mcp.to_string(),
            "--permission-mode",
            "dontAsk",
            "--allowedTools",
            "mcp__lunchpail__*",
            "--settings",
            "{\"disableAllHooks\":true}",
            "--setting-sources",
            "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--system-prompt",
            SYSTEM,
        ]);
    if !profile.model.trim().is_empty() {
        command.arg("--model").arg(&profile.model);
    }
    let mut process = Process::start(&mut command)?;
    use std::io::Write;
    process
        .input
        .as_mut()
        .context("No provider input")?
        .write_all(prompt(history).as_bytes())?;
    process.input.take();
    let mut response = String::new();
    loop {
        bridge.poll(runtime)?;
        let Some(value) = process.receive(runtime)? else {
            continue;
        };
        match value["type"].as_str().unwrap_or("") {
            "assistant" => {
                if let Some(content) = value["message"]["content"].as_array() {
                    response = content
                        .iter()
                        .filter_map(|v| v["text"].as_str())
                        .collect::<Vec<_>>()
                        .join("\n");
                }
            }
            "result" => {
                ensure!(
                    value["is_error"] != true,
                    "Claude Code could not complete this turn. Check CLI sign-in, model access and usage limits."
                );
                return Ok(value["result"].as_str().unwrap_or(&response).into());
            }
            _ => (),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;
    #[test]
    #[ignore = "Uses an explicitly selected installed CLI and its existing sign-in; supplies synthetic read-only app state"]
    fn signed_in_cli_calls_the_lunchpail_context_tool() {
        let provider = match std::env::var("LUNCHPAIL_TEST_CLI").unwrap().as_str() {
            "codex" => super::super::settings::Provider::Codex,
            "claude" => super::super::settings::Provider::ClaudeCode,
            _ => panic!("Choose codex or claude explicitly"),
        };
        let settings = Settings {
            provider,
            ..Settings::default()
        };
        let (tx, rx) = mpsc::channel();
        let handler = std::thread::spawn(move || {
            while let Ok(event) = rx.recv() {
                if let super::super::Event::Tool { name, reply, .. } = event {
                    assert_eq!(
                        name, "get_context",
                        "Probe allows only synthetic read-only context"
                    );
                    reply.send(json!({"selected_game":{"id":"fixture-only","title":"Blueberry Fixture 413"},"game_running":false})).unwrap();
                    return;
                }
            }
            panic!("CLI never called the app tool");
        });
        let cancel = AtomicBool::new(false);
        let history = [Message { role:"user".into(), content:"Read get_context exactly once, then tell me the selected game's title verbatim. Do not use any other tools or change anything. This is a read-only connection test.".into() }];
        let result = super::super::ask(&settings, &history, &mut Runtime::new(&cancel, &tx));
        drop(tx);
        let handled = handler.join();
        assert!(result.is_ok(), "{result:?}");
        handled.unwrap();
        assert!(result.unwrap().contains("Blueberry Fixture 413"));
    }
}
