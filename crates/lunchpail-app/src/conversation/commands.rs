//! Short play commands use a grounded catalog preference without inference,
//! then the same guarded launch workflow as every UI.
use super::{Message, Runtime};
use anyhow::{Result, ensure};
use serde_json::{Value, json};

#[derive(Debug, PartialEq)]
struct PlayRequest {
    title: String,
    platform: String,
}

fn title_request(text: &str) -> PlayRequest {
    let lower = text.to_lowercase();
    let mut words: Vec<_> = lower.split_whitespace().collect();
    if words.first() == Some(&"just") { words.remove(0); }
    if words.starts_with(&["the", "original"]) { words.drain(..2); }
    else if words.first() == Some(&"original") { words.remove(0); }
    let mut platform = String::new();
    if let Some(position) = words.iter().rposition(|w| *w == "on" || *w == "for") {
        let candidate = platform_answer(&words[position + 1..].join(" "));
        if position > 0 && crate::catalog::is_platform_query(&candidate) {
            platform = candidate;
            words.truncate(position);
        }
    }
    PlayRequest { title: words.join(" "), platform }
}

fn platform_answer(text: &str) -> String {
    let lower = text.to_lowercase();
    let mut words: Vec<_> = lower.split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty()).collect();
    while words.first().is_some_and(|w| ["just", "the", "original", "on", "for"].contains(w)) {
        words.remove(0);
    }
    while words.last().is_some_and(|w| ["version", "one", "please"].contains(w)) {
        words.pop();
    }
    words.join(" ")
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
    let PlayRequest { title, platform } = title_request(&words.join(" "));
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

const AMBIGUOUS: &str = "More than one game matches: ";

fn correction_text(text: &str) -> (String, bool) {
    let normalized = text.to_lowercase().replace(['\u{2019}', '\''], "")
        .split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ");
    for prefix in ["no i said ", "no i meant ", "no i mean ", "no its ", "no it is ",
                   "i said ", "i meant ", "i mean ", "its called ", "no "] {
        if let Some(rest) = normalized.strip_prefix(prefix) { return (rest.into(), true); }
    }
    (normalized, false)
}

fn confirmed_title(answer: &str, clarification: &Message, prior: &PlayRequest) -> Option<PlayRequest> {
    if !matches!(answer, "yes" | "yes please" | "correct" | "thats right" | "that is right") { return None; }
    let proposal = clarification.content.strip_prefix("Did you mean ")?.strip_suffix('?')?;
    if proposal.contains(", or ") { return None; } // "yes" cannot choose between titles.
    let candidate = title_request(proposal);
    if crate::title_match::similarity(&candidate.title, &prior.title).score < 0.72
        || !crate::catalog::is_platform_query(&candidate.platform) { return None; }
    if !prior.platform.is_empty()
        && crate::catalog::canonical_platform_query(&prior.platform)
            != crate::catalog::canonical_platform_query(&candidate.platform) { return None; }
    Some(candidate)
}

fn request_from_history(history: &[Message]) -> Option<PlayRequest> {
    let current = history.last()?;
    if current.role != "user" {
        return None;
    }
    if let Some(request) = play_request(&current.content) {
        return Some(request);
    }
    // A platform or repeated-title refinement keeps the immediately preceding
    // play intent. Do not depend on the assistant using one exact sentence.
    let previous = history.get(history.len().checked_sub(3)?)?;
    let clarification = &history[history.len() - 2];
    if previous.role != "user"
        || clarification.role != "assistant"
    {
        return None;
    }
    let mut request = request_from_history(&history[..history.len() - 2])?;
    let (answer, correction) = correction_text(&current.content);
    if let Some(confirmed) = confirmed_title(&answer, clarification, &request) { return Some(confirmed); }
    if correction && search_request(&answer).is_none() { return None; }
    let words: Vec<_> = answer
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    if words.is_empty()
        || words.len() > 24
        || words.iter().any(|w| {
            [
                "no", "not", "dont", "never", "cancel", "stop", "instead", "yes", "what", "why",
                "how", "which", "can", "could", "would", "is", "are", "and", "or", "it", "this",
                "that",
                "play", "launch", "start", "open", "find", "search",
                "delete", "remove", "enable", "disable", "help", "settings", "preferences",
            ]
            .contains(w)
        })
    {
        return None;
    }
    let repeated = title_request(&answer);
    if crate::assistant_tools::spoken_title_key(&repeated.title)
        == crate::assistant_tools::spoken_title_key(&request.title)
    {
        if !repeated.platform.is_empty() { request.platform = repeated.platform; }
        return Some(request);
    }
    let platform = platform_answer(&answer);
    if crate::catalog::is_platform_query(&platform) {
        request.platform = platform;
        return Some(request);
    }
    // "Just the original" is useful context, not a literal search query.
    if matches!(words.as_slice(), ["original"] | ["the", "original"] | ["just", "the", "original"]
        | ["the", "original", "one"] | ["just", "the", "original", "one"]) {
        request.platform.clear();
        return Some(request);
    }
    // Different ASR spellings of the same name are still the same request.
    // An explicit "no, I meant TITLE" may replace the title, but never turns
    // a negation, compound instruction or question into a launch command.
    if correction || crate::title_match::similarity(&repeated.title, &request.title).score >= 0.72 {
        request.title = repeated.title;
        if !repeated.platform.is_empty() { request.platform = repeated.platform; }
        return Some(request);
    }
    None
}

fn search_from_history(history: &[Message]) -> Option<PlayRequest> {
    let current = history.last()?;
    if current.role != "user" { return None; }
    let (corrected, correction) = correction_text(&current.content);
    if history.len() >= 3 {
        if let Some(prior) = search_from_history(&history[..history.len() - 2]) {
            if let Some(confirmed) = confirmed_title(&corrected, &history[history.len() - 2], &prior) {
                return Some(confirmed);
            }
        }
    }
    if correction {
        // Preserve a prior search's platform; do not invent an intent from a
        // correction to unrelated conversation or an abandoned play request.
        let prior = search_from_history(&history[..history.len().checked_sub(2)?])?;
        let title = search_request(&corrected)?;
        let mut request = title_request(&title);
        if request.platform.is_empty() { request.platform = prior.platform; }
        return Some(request);
    }
    let query = search_request(&current.content)?;
    let mut request = title_request(&query);
    if history.len() >= 3 {
        if let Some(prior) = search_from_history(&history[..history.len() - 2]) {
            if crate::title_match::similarity(&prior.title, &request.title).score >= 0.72
                && request.platform.is_empty() { request.platform = prior.platform; }
        }
    }
    Some(request)
}

fn search_request(text: &str) -> Option<String> {
    let lower = text.trim().trim_matches(['"', '\'']).to_lowercase();
    let mut query = lower.as_str();
    for prefix in ["can you ", "could you ", "would you "] {
        if let Some(rest) = query.strip_prefix(prefix) {
            query = rest;
            break;
        }
    }
    query = query.strip_prefix("please ").unwrap_or(query);
    let mut explicit_search = false;
    for prefix in [
        "search all games for ",
        "take me to ",
        "bring me to ",
        "navigate to ",
        "go to ",
        "pull up ",
        "bring up ",
        "search for ",
        "look for ",
        "look up ",
        "show me ",
        "find ",
        "search ",
    ] {
        if let Some(rest) = query.strip_prefix(prefix) {
            query = rest;
            explicit_search = true;
            break;
        }
    }
    if explicit_search {
        query = query.trim().trim_end_matches(['?', '.', '!']);
        query = query.strip_suffix(" please").unwrap_or(query);
        if ["settings", "preferences", "downloads", "library", "the library", "the settings", "the downloads"]
            .contains(&query)
        {
            return None; // These are app navigation, not game-title searches.
        }
    } else {
        query = lower.as_str(); // Politeness alone does not turn a question into a title.
    }
    let words: Vec<_> = query.split_whitespace().collect();
    if query.is_empty() || query.len() > 160 || words.len() > 16 || query.contains('?') {
        return None;
    }
    if words.iter().any(|word| {
        [
            "favorites",
            "favourites",
            "collection",
            "collections",
            "recent",
            "owned",
            "installed",
            "recommend",
            "recommendations",
            "best",
        ]
        .contains(word)
    }) {
        return None; // Preserve an explicitly requested scope or a recommendation question.
    }
    if [
        "i",
        "i'm",
        "im",
        "what",
        "which",
        "who",
        "how",
        "why",
        "when",
        "where",
        "can",
        "could",
        "would",
        "should",
        "is",
        "are",
        "do",
        "does",
        "did",
        "please",
        "lets",
        "let's",
        "let",
        "play",
        "open",
        "launch",
        "start",
        "stop",
        "cancel",
        "never",
        "don't",
        "dont",
        "no",
        "yes",
        "thanks",
        "thank",
        "hello",
        "hi",
        "hey",
        "turn",
        "enable",
        "disable",
        "mute",
        "unmute",
        "pause",
        "resume",
        "show",
        "go",
        "take",
        "bring",
        "pull",
        "navigate",
        "back",
        "switch",
        "add",
        "remove",
        "delete",
        "favorite",
        "unfavorite",
        "set",
        "help",
    ]
    .contains(&words[0])
    {
        return None;
    }
    Some(query.trim().to_owned())
}

/// "open my favorites" names a library shelf, not a game. Recognize the
/// shelf before the play/search paths can mistake it for a title.
fn shelf_request(text: &str) -> Option<(&'static str, &'static str)> {
    let text = text.to_lowercase().replace(['\u{2019}', '\''], "");
    let mut words: Vec<_> = text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .collect();
    let strip = |words: &mut Vec<&str>, phrases: &[&str]| {
        for phrase in phrases {
            let phrase: Vec<_> = phrase.split_whitespace().collect();
            if words.starts_with(&phrase) {
                words.drain(..phrase.len());
                return true;
            }
        }
        false
    };
    strip(&mut words, &["can you", "could you", "would you", "please"]);
    strip(&mut words, &["please"]);
    if !strip(
        &mut words,
        &[
            "open up", "open", "show me", "show", "go to", "take me to", "bring me to",
            "bring up", "pull up", "switch to", "navigate to", "jump to",
        ],
    ) {
        return None;
    }
    if words.is_empty() {
        return None;
    }
    strip(&mut words, &["all my", "all the", "my", "the", "all"]);
    while words.last().is_some_and(|w| {
        ["please", "shelf", "section", "list", "tab", "page", "category", "games"].contains(w)
    }) {
        words.pop();
    }
    Some(match words.join(" ").as_str() {
        "favorites" | "favourites" | "favorite" | "favourite" => ("favorites", "Favorites"),
        "recent" | "recents" | "recently played" => ("recent", "Recent"),
        "collection" | "installed" | "local" | "own" | "owned" => ("local", "My collection"),
        "minerva" | "downloadable" => ("downloadable", "Minerva"),
        "" => ("all", "All games"),
        _ => return None,
    })
}

fn browse_shelf(shelf: &str, label: &str, runtime: &mut Runtime<'_>) -> String {
    let result = runtime.invoke(
        "browse_library",
        json!({"query":"","platform":"","shelf":shelf,"collection_id":""}),
    );
    if let Some(error) = result["error"].as_str() {
        return error.into();
    }
    match result["total_results"].as_u64() {
        Some(0) => format!("Showing {label}. It's empty right now."),
        Some(1) => format!("Showing {label}: 1 game."),
        Some(count) => format!("Showing {label}: {count} games."),
        None => format!("Showing {label}."),
    }
}

fn browse_all(query: &str, platform: &str, runtime: &mut Runtime<'_>) -> Result<String> {
    browse_title(query, platform, runtime, false)
}

fn clarification(matches: &Value) -> Option<String> {
    if matches["match_kind"] != "ambiguous" { return None; }
    let names: Vec<_> = matches["games"].as_array()?.iter().take(3).filter_map(|game| {
        let title = game["title"].as_str()?;
        Some(format!("{title} for {}", game["platform"].as_str().unwrap_or("an unknown platform")))
    }).collect();
    (!names.is_empty()).then(|| format!("Did you mean {}?", names.join(", or ")))
}

fn browse_title(query: &str, platform: &str, runtime: &mut Runtime<'_>, recover: bool) -> Result<String> {
    let platform = crate::catalog::canonical_platform_query(platform).unwrap_or(platform);
    let result = runtime.invoke(
        "browse_library",
        json!({"query":query,"platform":platform,"shelf":"all","collection_id":""}),
    );
    if let Some(error) = result["error"].as_str() {
        return Ok(error.into());
    }
    let count = result["total_results"]
        .as_u64()
        .ok_or_else(|| anyhow::anyhow!("The library search did not return its result count"))?;
    Ok(if count == 0 && recover {
        let matched = runtime.invoke("resolve_game", json!({"title":query,"platform":platform}));
        if let Some(question) = clarification(&matched) { return Ok(question); }
        if matched["auto_resolved"] == true {
            if let Some(title) = matched["resolved_title"].as_str().filter(|t| *t != query) {
                let reply = browse_title(title, platform, runtime, false)?;
                return Ok(format!("I matched that to {title}. {reply}"));
            }
        }
        format!("I couldn't find a close catalog match for “{query}”. Which game or platform did you mean?")
    } else if count == 0 {
        format!("No matches for “{query}” in All Games.")
    } else {
        format!("Showing {count} matching games in All Games.")
    })
}

pub(super) fn try_command(
    history: &[Message],
    runtime: &mut Runtime<'_>,
) -> Result<Option<String>> {
    if let Some((shelf, label)) = history
        .last()
        .filter(|message| message.role == "user")
        .and_then(|message| shelf_request(&message.content))
    {
        runtime.invoke("get_context", json!({}));
        return Ok(Some(browse_shelf(shelf, label, runtime)));
    }
    let Some(request) = request_from_history(history) else {
        let Some(query) = search_from_history(history)
        else {
            return Ok(None);
        };
        runtime.invoke("get_context", json!({}));
        return browse_title(&query.title, &query.platform, runtime, true).map(Some);
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
    if let Some(question) = clarification(&matches) { return Ok(Some(question)); }
    let games = matches["games"].as_array();
    let total = matches["total_matches"].as_u64().unwrap_or(0);
    if total == 0 {
        let searched = browse_all(&request.title, &request.platform, runtime)?;
        return Ok(Some(format!(
            "I couldn't resolve an exact game to launch. {searched} I haven't launched anything."
        )));
    }
    let preferred = matches["preferred_game_id"].as_str().and_then(|id|
        games?.iter().find(|game| game["id"].as_str() == Some(id)));
    if total != 1 && preferred.is_none() {
        let searched = browse_all(&request.title, &request.platform, runtime)?;
        let choices = games
            .into_iter()
            .flatten()
            .take(8)
            .map(|g| g["platform"].as_str().unwrap_or("unknown platform"))
            .collect::<Vec<_>>()
            .join(", ");
        return Ok(Some(format!(
            "{AMBIGUOUS}{choices}. {searched} Which platform? I haven't launched anything."
        )));
    }
    let game = preferred.or_else(|| games.and_then(|g| g.first()))
        .ok_or_else(|| anyhow::anyhow!("The catalog returned an incomplete match"))?;
    let resolved_title = game["title"].as_str().unwrap_or("");
    let recovered = matches["match_kind"] == "approximate" && matches["auto_resolved"] == true
        && matches["resolved_title"] == resolved_title
        && crate::title_match::similarity(&request.title, resolved_title).score >= 0.74;
    ensure!(
        crate::assistant_tools::spoken_title_key(resolved_title)
            == crate::assistant_tools::spoken_title_key(&request.title) || recovered,
        "The resolved game does not match the requested title; nothing was launched"
    );
    let id = game["id"].as_str().unwrap_or("");
    ensure!(!id.is_empty(), "The catalog match has no game ID");
    runtime.check()?;
    let result = runtime.invoke("play_game", json!({"game_id":id}));
    let reply = launch_reply(game, &result);
    Ok(Some(if recovered {
        format!("{resolved_title} for {}. {reply}", game["platform"].as_str().unwrap_or("the matching platform"))
    } else if total > 1 {
        format!("I picked {} for {}. {reply}", game["title"].as_str().unwrap_or("the matching game"),
            game["platform"].as_str().unwrap_or("the matching platform"))
    } else { reply }))
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
    fn repeated_mishearings_and_explicit_corrections_preserve_play_intent() {
        let mut history = vec![Message { role:"user".into(), content:"play facsinidu for NES".into() }];
        for text in ["no, I said faxanadoo", "fax in a do", "Faxanadu"] {
            history.push(Message {role:"assistant".into(), content:"Which game did you mean?".into()});
            history.push(Message {role:"user".into(), content:text.into()});
            let request = request_from_history(&history).unwrap();
            assert_eq!(request.platform, "nes");
            assert!(crate::title_match::similarity(&request.title, "Faxanadu").score >= 0.8);
        }
        for text in ["no, don't play it", "no, stop", "no, what is Faxanadu", "no thanks", "no, open settings", "cancel", "no"] {
            history.last_mut().unwrap().content = text.into();
            assert!(request_from_history(&history).is_none(), "{text}");
        }
    }
    #[test]
    fn corrections_keep_search_intent_without_launching() {
        let mut history = vec![Message {role:"user".into(), content:"find facsinidu for NES".into()},
            Message {role:"assistant".into(), content:"Which title?".into()},
            Message {role:"user".into(), content:"no, I meant Faxanadu".into()}];
        assert!(request_from_history(&history).is_none());
        assert_eq!(search_from_history(&history).unwrap(), PlayRequest { title:"faxanadu".into(), platform:"nes".into() });
        history[0].content = "how are you".into();
        assert!(search_from_history(&history).is_none());
    }
    #[test]
    fn one_targeted_confirmation_is_enough_but_yes_cannot_choose_between_titles() {
        let mut history = vec![Message {role:"user".into(), content:"play facsinidu for NES".into()},
            Message {role:"assistant".into(), content:"Did you mean Faxanadu for Nintendo Entertainment System?".into()},
            Message {role:"user".into(), content:"yes".into()}];
        assert_eq!(request_from_history(&history).unwrap().title, "faxanadu");
        history[0].content = "find facsinidu for NES".into();
        assert_eq!(search_from_history(&history).unwrap().title, "faxanadu");
        assert!(request_from_history(&history).is_none());
        history[1].content = "Did you mean Faxanadu for NES, or Faksinadu for NES?".into();
        assert!(search_from_history(&history).is_none());
        history[1].content = "Did you mean Sonic for NES?".into();
        assert!(search_from_history(&history).is_none());
    }
    #[test]
    fn recovered_commands_use_canonical_ids_and_ambiguity_never_launches() {
        let resolved = json!({"games":[{"id":"fax","title":"Faxanadu","platform":"NES"}],
            "total_matches":1,"preferred_game_id":"fax","match_kind":"approximate",
            "auto_resolved":true,"resolved_title":"Faxanadu"});
        let (reply, calls) = run_query(resolved.clone(), false, "play facsinidu");
        assert!(reply.unwrap().starts_with("Faxanadu for NES."));
        assert_eq!(calls.last().unwrap().1, json!({"game_id":"fax"}));
        let mut ambiguous = resolved;
        ambiguous["match_kind"] = json!("ambiguous");
        ambiguous["auto_resolved"] = json!(false);
        ambiguous["preferred_game_id"] = Value::Null;
        let (reply, calls) = run_query(ambiguous, false, "play facsinidu");
        assert_eq!(reply.unwrap(), "Did you mean Faxanadu for NES?");
        assert!(calls.iter().all(|c| c.0 != "play_game" && c.0 != "browse_library"));
    }

    #[test]
    fn a_platform_clarification_keeps_the_requested_title_not_the_selection() {
        let mut history = vec![
            Message {
                role: "user".into(),
                content: "let's play some super mario brothers".into(),
            },
            Message {
                role: "assistant".into(),
                content: format!(
                    "{AMBIGUOUS}NES, FDS. Which platform? I haven't launched anything."
                ),
            },
            Message {
                role: "user".into(),
                content: "the original NES version".into(),
            },
        ];
        assert_eq!(
            request_from_history(&history).unwrap(),
            PlayRequest {
                title: "super mario brothers".into(),
                platform: "nes".into()
            }
        );
        history[2].content = "never mind".into();
        assert!(request_from_history(&history).is_none());
        history[2].content = "what is NES?".into();
        assert!(request_from_history(&history).is_none());
        history[2].content = "NES".into();
        history[0].content = "tell me about Mario".into();
        assert!(request_from_history(&history).is_none());
    }

    #[test]
    fn original_title_and_platform_refinements_keep_the_play_intent() {
        for answer in ["just the original super mario bros for nes", "the original Super Mario Brothers on the N ES please", "Super Mario Bros. for Nintendo Entertainment System", "just the original NES version"] {
            let history = vec![
                Message {role:"user".into(), content:"let's play Super Mario Bros".into()},
                Message {role:"assistant".into(), content:"Which system?".into()},
                Message {role:"user".into(), content:answer.into()},
            ];
            let request = request_from_history(&history).unwrap();
            assert_eq!(request.title, "super mario bros", "{answer}");
            assert!(crate::catalog::is_platform_query(&request.platform), "{answer}");
        }
        let mut history = vec![
            Message {role:"user".into(), content:"play Super Mario Bros".into()},
            Message {role:"assistant".into(), content:"Which system?".into()},
            Message {role:"user".into(), content:"just the original".into()},
        ];
        assert_eq!(request_from_history(&history).unwrap().title, "super mario bros");
        history.push(Message {role:"assistant".into(), content:"Which platform?".into()});
        history.push(Message {role:"user".into(), content:"n es".into()});
        assert_eq!(request_from_history(&history).unwrap().platform, "n es");
        for answer in ["cancel", "don't play it", "what is NES?", "Sonic for NES"] {
            history.last_mut().unwrap().content = answer.into();
            assert!(request_from_history(&history).is_none(), "{answer}");
        }
    }

    #[test]
    fn platform_qualifiers_do_not_leak_into_title_searches() {
        for question in ["just the original Super Mario Brothers for NES", "take me to Super Mario Brothers on the n es", "find Super Mario Brothers for the NES version"] {
            let (reply, calls) = run_query(json!({}), false, question);
            assert!(reply.is_ok());
            assert_eq!(calls[1].1["query"], "super mario brothers", "{question}");
            assert!(crate::catalog::is_platform_query(calls[1].1["platform"].as_str().unwrap()));
            assert_eq!(calls[1].0, "browse_library");
        }
        assert_eq!(title_request("Need for Speed").title, "need for speed");
        assert_eq!(play_request("play the original Super Mario Bros for NES").unwrap().title, "super mario bros");
    }

    #[test]
    fn ranked_catalog_preference_avoids_a_platform_question() {
        let (reply, calls) = run(json!({"total_matches":25,"preferred_game_id":"nes",
            "games":[{"id":"nes","title":"Super Mario Bros.","platform":"NES"},
                     {"id":"port","title":"Super Mario Bros.","platform":"C64"}]}), false);
        let reply = reply.unwrap();
        assert!(reply.contains("I picked Super Mario Bros. for NES."));
        assert!(!reply.contains("Which platform"));
        assert_eq!(calls.last().unwrap().1, json!({"game_id":"nes"}));
        assert!(calls.iter().all(|c| c.0 != "browse_library"));
    }

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
        run_query(matches, cancelled, "let's play some super mario brothers")
    }

    fn run_query(
        matches: Value,
        cancelled: bool,
        question: &str,
    ) -> (Result<String>, Vec<(String, Value)>) {
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
                            json!({"selected_game":{"id":"faxanadu","title":"Faxanadu"},"game_running":false,"screen":{"shelf":"favorites"}})
                        }
                        "resolve_game" => matches.clone(),
                        "browse_library" => {
                            json!({"total_results":61,"games":[{"id":"mario","title":"Super Mario Bros."}],"screen":{"shelf":""}})
                        }
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
                content: question.into(),
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
    fn shelf_names_open_the_shelf_instead_of_searching_titles() {
        for (question, shelf) in [
            ("open up my favorites", "favorites"),
            ("Open my favourites please", "favorites"),
            ("can you show me my favorites?", "favorites"),
            ("go to recently played games", "recent"),
            ("take me to my collection", "local"),
            ("show all games", "all"),
        ] {
            let (reply, calls) = run_query(json!({}), false, question);
            assert!(reply.unwrap().starts_with("Showing "), "{question}");
            assert_eq!(
                calls.iter().map(|c| c.0.as_str()).collect::<Vec<_>>(),
                ["get_context", "browse_library"],
                "{question}"
            );
            assert_eq!(
                calls[1].1,
                json!({"query":"","platform":"","shelf":shelf,"collection_id":""}),
                "{question}"
            );
        }
        for text in ["open", "open Super Mario Bros", "show me Mario in favorites", "play my favorite game"] {
            assert!(shelf_request(text).is_none(), "{text}");
        }
    }

    #[test]
    fn bare_and_search_titles_automatically_leave_favorites_for_all_games() {
        for question in [
            "SUPER MARIO BROTHERS",
            "find Super Mario Brothers",
            "search all games for Super Mario Brothers",
            "take me to super mario brothers",
            "Take me to Super Mario Brothers please",
            "Could you please take me to Super Mario Brothers?",
            "go to Super Mario Brothers",
            "pull up Super Mario Brothers",
        ] {
            let (reply, calls) = run_query(json!({}), false, question);
            assert_eq!(reply.unwrap(), "Showing 61 matching games in All Games.");
            assert_eq!(
                calls.iter().map(|c| c.0.as_str()).collect::<Vec<_>>(),
                ["get_context", "browse_library"]
            );
            assert_eq!(
                calls[1].1,
                json!({"query":"super mario brothers","platform":"","shelf":"all","collection_id":""})
            );
        }
        for question in [
            "what is Super Mario Brothers?",
            "show settings",
            "pause",
            "find Mario in favorites",
            "recommend a good game",
            "take me to settings",
            "go to downloads",
            "take a screenshot",
            "please don't search for Mario",
            "could you explain Mario?",
        ] {
            assert!(search_request(question).is_none(), "{question}");
        }
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
