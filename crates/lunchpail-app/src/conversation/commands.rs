//! Short, explicit play commands do not need model inference. Resolve a unique
//! exact catalog title, then use the same guarded launch workflow as every UI.
use super::Runtime;
use anyhow::{Result, ensure};
use serde_json::{Value, json};

#[derive(Debug, PartialEq)]
struct PlayRequest {
    title: String,
    platform: String,
}

fn play_request(text: &str) -> Option<PlayRequest> {
    let text = text.to_lowercase().replace(['\u{2019}', '\''], "");
    let mut words: Vec<_> = text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .collect();
    // Keep compound, hypothetical and negated requests with the conversational
    // provider. This path only acts on a single affirmative launch instruction.
    if words.iter().any(|w| {
        [
            "not", "dont", "never", "without", "instead", "except", "unless", "if", "before",
            "after", "then", "but", "and", "or",
        ]
        .contains(w)
    }) {
        return None;
    }
    if words.first() == Some(&"please") {
        words.remove(0);
    }
    for prefix in [
        "can you",
        "could you",
        "would you",
        "lets",
        "let us",
        "i want to",
        "id like to",
    ] {
        let prefix: Vec<_> = prefix.split_whitespace().collect();
        if words.starts_with(&prefix) {
            words.drain(..prefix.len());
            break;
        }
    }
    if words.first() == Some(&"please") {
        words.remove(0);
    }
    if !words
        .first()
        .is_some_and(|w| ["play", "launch", "start", "open"].contains(w))
    {
        return None;
    }
    let verb = words.remove(0);
    if words.first() == Some(&"up") {
        words.remove(0);
    }
    if verb == "play" && words.first() == Some(&"some") {
        words.remove(0);
    }
    if words.last() == Some(&"please") {
        words.pop();
    }
    if words.is_empty() || words.len() > 24 {
        return None;
    }
    let mut platform = String::new();
    if let Some(position) = words.iter().rposition(|w| *w == "on" || *w == "for") {
        if position > 0 && position + 1 < words.len() {
            platform = words[position + 1..].join(" ");
            words.truncate(position);
        }
    }
    let title = words.join(" ");
    if verb == "open"
        && words.iter().any(|w| {
            [
                "settings",
                "preferences",
                "downloads",
                "collections",
                "assistant",
            ]
            .contains(w)
        })
    {
        return None;
    }
    if [
        "it",
        "this",
        "that",
        "this one",
        "that one",
        "this game",
        "that game",
        "the game",
        "the selected game",
        "the highlighted game",
        "a game",
        "something",
        "anything",
        "music",
        "the music",
        "video",
        "the video",
        "preview",
        "the preview",
        "settings",
        "the settings",
        "downloads",
        "library",
        "the library",
        "details",
        "the details",
    ]
    .contains(&title.as_str())
    {
        return None;
    }
    if title.len() > 160 || platform.len() > 100 {
        return None;
    }
    Some(PlayRequest { title, platform })
}

pub(super) fn try_play(text: &str, runtime: &mut Runtime<'_>) -> Result<Option<String>> {
    let Some(request) = play_request(text) else {
        return Ok(None);
    };
    runtime.status("Finding the requested game…");
    let context = runtime.invoke("get_context", json!({}));
    if let Some(error) = context["error"].as_str() {
        return Ok(Some(error.into()));
    }
    // Respect running games and pending user choices. Never stop or replace one
    // just because another title was requested.
    if context["game_running"] == true {
        return Ok(Some(
            "A game is already running. Stop it before starting another game.".into(),
        ));
    }
    if context["launch_busy"] == true {
        return Ok(Some(
            "A launch is already in progress. Please finish that first.".into(),
        ));
    }
    if context["screen"]["confirmation_open"] == true || context["screen"]["launch_pending"] == true
    {
        return Ok(Some(
            "Please finish the current save/resume or setup prompt before launching another game."
                .into(),
        ));
    }
    let matches = runtime.invoke(
        "resolve_game",
        json!({"title":request.title,"platform":request.platform}),
    );
    if let Some(error) = matches["error"].as_str() {
        return Ok(Some(error.into()));
    }
    let games = matches["games"].as_array();
    let total = matches["total_matches"].as_u64().unwrap_or(0);
    if total == 0 {
        return Ok(Some(format!(
            "I couldn't find an exact match for “{}”{}. Please give the full title or choose it in the library; I haven't launched anything.",
            request.title,
            if request.platform.is_empty() {
                String::new()
            } else {
                format!(" on {}", request.platform)
            }
        )));
    }
    if total != 1 {
        let choices = games
            .into_iter()
            .flatten()
            .take(5)
            .map(|g| {
                format!(
                    "{} ({})",
                    g["title"].as_str().unwrap_or("Unknown title"),
                    g["platform"].as_str().unwrap_or("unknown platform")
                )
            })
            .collect::<Vec<_>>()
            .join(", ");
        return Ok(Some(format!(
            "More than one game matches: {choices}. Please say play, the exact title, and its platform. I haven't launched anything."
        )));
    }
    let game = games
        .and_then(|g| g.first())
        .ok_or_else(|| anyhow::anyhow!("The catalog returned an incomplete match"))?;
    ensure!(
        crate::assistant_tools::spoken_title_key(game["title"].as_str().unwrap_or(""))
            == crate::assistant_tools::spoken_title_key(&request.title),
        "The resolved game does not match the requested title; nothing was launched"
    );
    let id = game["id"].as_str().unwrap_or("");
    ensure!(!id.is_empty(), "The catalog match has no game ID");
    runtime.check()?;
    let result = runtime.invoke("play_game", json!({"game_id":id}));
    Ok(Some(launch_reply(game, &result)))
}

fn launch_reply(game: &Value, result: &Value) -> String {
    if let Some(error) = result["error"].as_str() {
        return error.into();
    }
    let title = game["title"].as_str().unwrap_or("The game");
    match result["status"].as_str().unwrap_or("") {
        "running" => format!("{title} is running."),
        "setup_required" => format!("{title} isn't installed. Its details are open for download or import."),
        _ => result["message"].as_str().unwrap_or("The launch was requested but is not confirmed running. Check the app for a setup or save/resume prompt.").into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conversation::{Event, Message, ask, settings::Settings};
    use std::sync::{atomic::AtomicBool, mpsc};

    #[test]
    fn recognizes_natural_title_commands_without_swallowing_other_intents() {
        for text in [
            "let's play some super mario brothers",
            "Let’s play some Super Mario Brothers!",
            "open up super mario brothers",
            "Can you please launch Super Mario Brothers?",
            "please play super mario brothers please",
        ] {
            assert_eq!(
                play_request(text).unwrap(),
                PlayRequest {
                    title: "super mario brothers".into(),
                    platform: String::new()
                },
                "{text}"
            );
        }
        assert_eq!(
            play_request("play Super Mario Bros. on NES").unwrap(),
            PlayRequest {
                title: "super mario bros".into(),
                platform: "nes".into()
            }
        );
        for text in [
            "don't play Mario",
            "play Mario but not Faxanadu",
            "if I play Mario",
            "play this",
            "open settings",
            "play the video",
            "could we play something like Mario",
            "play Mario and Zelda",
        ] {
            assert!(play_request(text).is_none(), "{text}");
        }
    }

    fn run(matches: Value, cancelled: bool) -> (Result<String>, Vec<(String, Value)>) {
        let (tx, rx) = mpsc::channel();
        let ui = std::thread::spawn(move || {
            let mut calls = Vec::new();
            while let Ok(event) = rx.recv() {
                if let Event::Tool {
                    name,
                    arguments,
                    reply,
                    ..
                } = event
                {
                    let result = match name.as_str() {
                        "get_context" => {
                            json!({"selected_game":{"id":"faxanadu","title":"Faxanadu"},"game_running":false})
                        }
                        "resolve_game" => matches.clone(),
                        "play_game" => json!({"status":"setup_required"}),
                        _ => panic!("Unexpected tool {name}"),
                    };
                    calls.push((name, arguments));
                    let _ = reply.send(result);
                }
            }
            calls
        });
        let cancel = AtomicBool::new(cancelled);
        let mut runtime = Runtime::new(&cancel, &tx);
        let result = ask(
            &Settings::default(),
            &[Message {
                role: "user".into(),
                content: "let's play some super mario brothers".into(),
            }],
            &mut runtime,
        );
        // A resolved ID must not cause an expensive database/model load. The
        // synthetic ID also proves tests cannot accidentally launch a real game.
        assert!(runtime.catalog.is_none());
        drop(tx);
        (result, ui.join().unwrap())
    }

    #[test]
    fn named_game_never_falls_back_to_faxanadu_and_never_loads_a_model() {
        let (reply, calls) = run(
            json!({"games":[{"id":"mario","title":"Super Mario Bros.","platform":"NES"}],"total_matches":1}),
            false,
        );
        assert!(reply.unwrap().contains("isn't installed"));
        assert_eq!(
            calls.iter().map(|c| c.0.as_str()).collect::<Vec<_>>(),
            ["get_context", "resolve_game", "play_game"]
        );
        assert_eq!(
            calls[1].1,
            json!({"title":"super mario brothers","platform":""})
        );
        assert_eq!(calls[2].1, json!({"game_id":"mario"}));
    }

    #[test]
    fn missing_ambiguous_and_cancelled_commands_never_launch_the_selection() {
        for matches in [
            json!({"games":[],"total_matches":0}),
            json!({"games":[{"id":"mario","title":"Super Mario Bros.","platform":"NES"}],"total_matches":21}),
        ] {
            let (reply, calls) = run(matches, false);
            assert!(reply.unwrap().contains("haven't launched anything"));
            assert!(calls.iter().all(|c| c.0 != "play_game"));
        }
        let (reply, calls) = run(json!({}), true);
        assert!(reply.is_err());
        assert!(calls.is_empty());
        let (reply, calls) = run(
            json!({"games":[{"id":"faxanadu","title":"Faxanadu"}],"total_matches":1}),
            false,
        );
        assert!(reply.unwrap_err().to_string().contains("does not match"));
        assert!(calls.iter().all(|c| c.0 != "play_game"));
    }

    #[test]
    fn launch_status_is_observed_not_assumed() {
        let game = json!({"title":"Mario"});
        assert_eq!(
            launch_reply(&game, &json!({"status":"running"})),
            "Mario is running."
        );
        assert_eq!(
            launch_reply(
                &game,
                &json!({"status":"user_action_required","message":"Choose a save"})
            ),
            "Choose a save"
        );
        assert_eq!(
            launch_reply(&game, &json!({"error":"Firmware missing"})),
            "Firmware missing"
        );
        assert!(
            launch_reply(&game, &json!({"status":"pending"})).contains("not confirmed running")
        );
    }
}
