//! The same narrowly typed, read-only tools serve the built-in assistant and
//! MCP. Never accept SQL, shell commands, file paths, or model-supplied URLs.
use crate::{
    catalog::{self, Catalog},
    list_view::ListColumn,
    patch_catalog,
};
use anyhow::{Context, Result, ensure};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SearchGames {
    /// Title words, or empty to browse a genre/platform.
    #[serde(default)]
    pub query: String,
    /// Canonical platform or alias such as SNES, PS1, GBA. Empty means all.
    #[serde(default)]
    pub platform: String,
    /// Genre filter. RPG and JRPG match catalog Role-Playing metadata.
    #[serde(default)]
    pub genre: String,
    #[serde(default)]
    pub owned_only: bool,
    #[serde(default = "default_limit")]
    pub limit: u32,
}
fn default_limit() -> u32 {
    12
}

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GameDetails {
    pub game_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TranslationPatches {
    /// Exact game ID from search_games. The game supplies the search title/platform.
    pub game_id: String,
    /// Optional original-language or shortened title. Empty uses the catalog
    /// title. Results remain candidates and may refer to a different revision.
    #[serde(default)]
    pub query: String,
    /// archive is a partial 2019 snapshot; plaza needs the user's saved API key;
    /// github searches inspected project releases and may be rate limited.
    #[serde(default = "default_provider")]
    pub provider: String,
}
fn default_provider() -> String {
    "archive".into()
}

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(
    tag = "tool",
    content = "arguments",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum ToolCall {
    SearchGames(SearchGames),
    GameDetails(GameDetails),
    TranslationPatches(TranslationPatches),
}

#[derive(Clone, Debug, Serialize)]
pub struct GameCard {
    pub id: String,
    pub title: String,
    pub platform: String,
    pub database_id: i64,
    pub local: bool,
    pub downloadable: bool,
    pub genre: String,
    pub rating: String,
    pub year: String,
    pub description: String,
}

pub struct ToolContext {
    catalog: Arc<Catalog>,
}

fn key(text: &str) -> String {
    catalog::normalize_platform_key(text).replace('-', "")
}

pub(crate) fn spoken_title_key(title: &str) -> String {
    crate::title_match::key(title)
}

#[derive(Default)]
pub(crate) struct TitleContext {
    /// Recent user utterances, not instructions or provider-generated facts.
    pub utterances: Vec<String>,
    pub selected_id: String,
    pub recent_ids: Vec<String>,
}

/// The exact resolver remains the source of IDs and release/platform ordering.
/// Approximate recovery only chooses a *title*, never a different sequel or
/// an arbitrary currently selected game. Scores are heuristics, not ASR odds.
pub(crate) fn match_game(catalog: &Catalog, title: &str, platform: &str, context: &TitleContext) -> Value {
    let mut exact = resolve_game(catalog, title, platform);
    if exact["total_matches"].as_u64().unwrap_or(0) > 0 {
        exact["match_kind"] = json!("exact");
        exact["auto_resolved"] = json!(true);
        exact["requested_title"] = json!(title);
        exact["resolved_title"] = exact["games"][0]["title"].clone();
        return exact;
    }
    let query_key = spoken_title_key(title);
    let utterances: Vec<_> = context.utterances.iter().rev().take(8)
        .map(|text| spoken_title_key(&text.chars().take(1000).collect::<String>())).collect();
    struct Candidate<'a> { title: &'a str, key: String, score: f64, mentioned: bool, base: crate::title_match::Similarity }
    let mut candidates: HashMap<String, Candidate<'_>> = HashMap::new();
    for game in &catalog.games {
        if game.adult || game.non_retail || !platform_matches(&game.platform, platform)
            || game.title.len() > title.len().saturating_mul(2) + 16
            || !crate::title_match::compatible_initial(title, &game.title) { continue; }
        let game_key = spoken_title_key(&game.title);
        // Only compute edit distances once per title, even for large port catalogs.
        let base = candidates.get(&game_key).map(|c| c.base)
            .unwrap_or_else(|| crate::title_match::similarity(title, &game.title));
        if base.score == 0.0 { continue; }
        let mentioned = game_key.len() >= 5 && utterances.iter().any(|u| u.contains(&game_key));
        let boost = if mentioned { 0.065 } else { 0.0 }
            + if context.recent_ids.contains(&game.id) { 0.025 } else { 0.0 }
            + if context.selected_id == game.id { 0.01 } else { 0.0 }
            + if game.local { 0.01 } else { 0.0 };
        let score = base.score + boost;
        let entry = candidates.entry(game_key.clone()).or_insert(Candidate {
            title: &game.title, key: game_key, score, mentioned, base,
        });
        entry.score = entry.score.max(score);
    }
    let mut candidates: Vec<_> = candidates.into_values().collect();
    candidates.sort_by(|a, b| b.score.total_cmp(&a.score).then_with(|| a.key.cmp(&b.key)));
    let Some(best) = candidates.first() else {
        return json!({"games":[],"total_matches":0,"preferred_game_id":null,
            "match_kind":"none","auto_resolved":false,"requested_title":title});
    };
    let margin = best.score - candidates.get(1).map_or(0.0, |c| c.score);
    let strong_base = best.base.spelling >= 0.55 && best.base.score >= 0.80;
    let contextual_recovery = best.mentioned && best.base.spelling >= 0.5
        && best.base.phonetic >= 0.85 && best.base.score >= 0.74;
    let confident = query_key.len() >= 5 && (strong_base || contextual_recovery)
        && best.base.phonetic >= 0.82
        && best.score >= 0.84 && margin >= 0.075;
    if confident {
        let mut result = resolve_game(catalog, best.title, platform);
        result["match_kind"] = json!("approximate");
        result["auto_resolved"] = json!(true);
        result["requested_title"] = json!(title);
        result["resolved_title"] = json!(best.title);
        result["similarity"] = json!(best.base.score);
        result["candidate_margin"] = json!(margin);
        return result;
    }
    let mut games = Vec::new();
    for candidate in candidates.iter().take(3) {
        let result = resolve_game(catalog, candidate.title, platform);
        if let Some(game) = result["games"].as_array().and_then(|games| games.first()) {
            games.push(game.clone());
        }
    }
    json!({"total_matches":games.len(),"games":games,"preferred_game_id":null,
        "match_kind":"ambiguous","auto_resolved":false,"requested_title":title,
        "instruction":"These are suggestions, not a resolved request. Ask the user which title they meant before selecting or launching anything."})
}

/// Small, bounded vocabulary for speech decoding. Recent/selected titles are
/// hints only; they never limit catalog matching or become launch defaults.
pub(crate) fn speech_titles(catalog: &Catalog, context: &TitleContext, visible: &[usize]) -> Vec<String> {
    let utterances: Vec<_> = context.utterances.iter().rev().take(8)
        .map(|text| spoken_title_key(&text.chars().take(1000).collect::<String>())).collect();
    let mut ranked = Vec::new();
    for (index, game) in catalog.games.iter().enumerate() {
        if game.adult || game.non_retail || game.title.len() > 100 { continue; }
        let priority = if game.id == context.selected_id { 0 }
            else if let Some(rank) = context.recent_ids.iter().take(12).position(|id| id == &game.id) { 2 + rank }
            else if visible.iter().take(16).any(|i| *i == index) { 20 }
            else if !utterances.is_empty() {
                let title = spoken_title_key(&game.title);
                if title.len() >= 5 && utterances.iter().any(|u| u.contains(&title)) { 1 } else { continue; }
            } else { continue; };
        ranked.push((priority, &game.title));
    }
    ranked.sort();
    let mut seen = std::collections::HashSet::new();
    ranked.into_iter().filter_map(|(_, title)| seen.insert(spoken_title_key(title)).then(|| title.clone()))
        .take(32).collect()
}

/// Resolve against the already-loaded catalog, not the selected game or a
/// truncated search sample. Rank the full set before bounding the tool context.
/// Prefer an early, well-documented retail release, then installed/available
/// copies. No title or platform is hard-coded as the winner.
pub(crate) fn resolve_game(catalog: &Catalog, title: &str, platform: &str) -> Value {
    let title = spoken_title_key(title);
    let mut matches: Vec<_> = catalog.games.iter().enumerate().filter(|(_, game)| {
        !title.is_empty() && !game.adult && !game.non_retail
            && platform_matches(&game.platform, platform)
            && spoken_title_key(&game.title) == title
    }).map(|(index, game)| {
        let (year, date) = catalog.list_metadata.release_chronology(index);
        (game, year.filter(|year| (1900..=2200).contains(year)), date.unwrap_or(""))
    }).collect();
    matches.sort_by_key(|(game, year, date)| (
        year.unwrap_or(i32::MAX), date.len() < 10, *date,
        !game.local, !game.downloadable, game.platform.clone(), game.id.clone(),
    ));
    let rows: Vec<_> = matches.iter().take(20).map(|(game, year, date)| json!({
        "id":game.id,"title":game.title,"platform":game.platform,
        "local":game.local,"downloadable":game.downloadable,
        "year":year,"release_date":date,
    })).collect();
    let reason = if matches.first().is_some_and(|(_, year, _)| year.is_some()) {
        "earliest documented release year, preferring a complete date; availability breaks ties"
    } else { "release dates unavailable; prefer installed, then downloadable copies" };
    json!({"preferred_game_id":matches.first().map(|(game, _, _)| &game.id),
        "selection_reason":reason,
        "games":rows,"total_matches":matches.len()})
}

/// Keep exact title matches in the bounded assistant context even when a
/// crowded alphabetical result list would otherwise truncate them away.
/// This reorders only the tool's sample, never the user's browser or selection.
pub(crate) fn conversation_indices(catalog: &Catalog, indices: &[usize], query: &str) -> Vec<usize> {
    let query = spoken_title_key(query);
    if query.is_empty() { return indices.iter().copied().take(16).collect(); }
    let mut exact = Vec::new();
    let mut others = Vec::new();
    for &index in indices {
        let Some(game) = catalog.games.get(index) else { continue; };
        if spoken_title_key(&game.title) == query {
            exact.push(index);
            if exact.len() == 16 { break; }
        } else if others.len() < 16 { others.push(index); }
    }
    exact.extend(others.into_iter().take(16 - exact.len()));
    exact
}
fn platform_matches(platform: &str, query: &str) -> bool {
    query.is_empty()
        || key(platform) == key(query)
        || catalog::legacy_platform_search_aliases(platform)
            .is_some_and(|aliases| aliases.split(',').any(|alias| key(alias) == key(query)))
}
fn genre_matches(genre: &str, query: &str) -> bool {
    let query = key(query);
    query.is_empty()
        || key(genre).contains(
            if matches!(query.as_str(), "jrpg" | "rpg" | "japaneserpg") {
                "roleplaying"
            } else {
                &query
            },
        )
}

impl ToolContext {
    pub fn load() -> Result<Self> {
        let path = catalog::requested_database_path()
            .context("No game catalog found. Open Lunchpail and configure the library first.")?;
        Ok(Self {
            catalog: Arc::new(catalog::load(&path)?),
        })
    }
    fn card(&self, index: usize) -> GameCard {
        let game = &self.catalog.games[index];
        let overrides = HashMap::new();
        let value = |column| {
            self.catalog
                .list_metadata
                .display_value(index, game, column, &overrides)
        };
        GameCard {
            id: game.id.clone(),
            title: game.title.clone(),
            platform: game.platform.clone(),
            database_id: game.launchbox_db_id,
            local: game.local,
            downloadable: game.downloadable,
            genre: value(ListColumn::Genre),
            rating: value(ListColumn::Rating),
            year: value(ListColumn::Year),
            description: value(ListColumn::Notes).chars().take(1200).collect(),
        }
    }
    pub fn game(&self, id: &str) -> Result<GameCard> {
        ensure!(id.len() <= 200, "Invalid game ID");
        let index = self
            .catalog
            .games
            .iter()
            .position(|g| g.id == id && !g.adult && !g.non_retail)
            .context("Game ID is not in the visible retail catalog")?;
        Ok(self.card(index))
    }
    pub fn search(&self, args: &SearchGames) -> Result<Value> {
        ensure!(
            args.query.len() <= 160 && args.platform.len() <= 100 && args.genre.len() <= 100,
            "Search filter is too long"
        );
        ensure!(
            (1..=20).contains(&args.limit),
            "Search limit must be between 1 and 20"
        );
        let words: Vec<_> = args
            .query
            .split_whitespace()
            .map(spoken_title_key)
            .filter(|s| !s.is_empty())
            .collect();
        let mut cards: Vec<_> = self
            .catalog
            .games
            .iter()
            .enumerate()
            .filter(|(_, game)| {
                !game.adult
                    && !game.non_retail
                    && (!args.owned_only || game.local)
                    && platform_matches(&game.platform, &args.platform)
                    && words.iter().all(|word| spoken_title_key(&game.title).contains(word))
            })
            .map(|(i, _)| self.card(i))
            .filter(|card| genre_matches(&card.genre, &args.genre))
            .collect();
        let mut resolution = Value::Null;
        if cards.is_empty() && !words.is_empty() {
            resolution = match_game(&self.catalog, &args.query, &args.platform, &TitleContext::default());
            if let Some(games) = resolution["games"].as_array() {
                cards = games.iter().filter_map(|candidate| {
                    let id = candidate["id"].as_str()?;
                    let index = self.catalog.games.iter().position(|game| game.id == id)?;
                    let card = self.card(index);
                    ((!args.owned_only || card.local) && genre_matches(&card.genre, &args.genre)).then_some(card)
                }).collect();
            }
            if cards.is_empty() { resolution = Value::Null; }
        }
        cards.sort_by(|a, b| {
            let rating = |card: &GameCard| card.rating.parse::<f32>().unwrap_or(0.0);
            rating(b)
                .total_cmp(&rating(a))
                .then_with(|| a.title.cmp(&b.title))
                .then_with(|| a.id.cmp(&b.id))
        });
        let total = cards.len();
        cards.truncate(args.limit as usize);
        // Short search rows preserve space for the next grounded tool turn.
        for card in &mut cards {
            card.description = card.description.chars().take(220).collect();
        }
        Ok(
            json!({"games":cards,"total_matches":total,"resolution":resolution,"note":"Ratings are catalog metadata, not a guarantee. JRPG maps to Role-Playing; region/origin is not inferred. Adult and non-retail entries are excluded. Approximate suggestions marked ambiguous require a user clarification before selection or launch."}),
        )
    }
    pub fn patches(&self, args: &TranslationPatches, cancel: &AtomicBool) -> Result<Value> {
        ensure!(
            matches!(args.provider.as_str(), "archive" | "plaza" | "github"),
            "Unknown patch provider"
        );
        let game = self.game(&args.game_id)?;
        let title = if args.query.trim().is_empty() {
            &game.title
        } else {
            args.query.trim()
        };
        ensure!(
            (2..=160).contains(&title.len()),
            "Patch search title must be 2–160 characters"
        );
        let report = patch_catalog::search_report(
            &args.provider,
            title,
            &game.platform,
            "translations",
            cancel,
        )?;
        let mut notes = vec![report.note];
        let mut rows = Vec::new();
        for mut entry in report.entries.into_iter().take(5) {
            if entry.provider == "plaza" {
                match patch_catalog::details(entry.clone(), cancel) {
                    Ok(details) => entry = details,
                    Err(error) => notes.push(format!(
                        "Metadata lookup incomplete for {}: {error:#}",
                        entry.title
                    )),
                }
            }
            rows.push(json!({
            "id":format!("{}:{}:{}", game.id, entry.provider, entry.id),
            "game_id":game.id,"title":entry.title,"provider":entry.provider,"language":entry.language,
            "version":entry.version,"source_url":entry.source_url,
            "description":entry.description.chars().take(700).collect::<String>(),
            "base_rom_requirements":entry.bases,"verification":entry.verification,
            "compatibility":"unknown — your ROM has not been checked",
            "completion":"unknown unless explicitly stated by the patch source",
            }));
        }
        Ok(
            json!({"game_id":game.id,"searched_title":title,"patches":rows,"provider_note":notes.join(" "),
            "coverage":if args.provider == "archive" { "Partial historical 2019 snapshot. A missing result does not mean no translation exists; newer revisions may exist." } else { "Provider search is not exhaustive; source results may be incomplete or rate limited." },
            "matching":"Title search produces candidates, not proof of the correct game/version. Inspect source and base-ROM requirements before use."}),
        )
    }
    pub fn call(&self, call: &ToolCall, cancel: &AtomicBool) -> Result<Value> {
        ensure!(!cancel.load(Ordering::Relaxed), "Assistant cancelled");
        match call {
            ToolCall::SearchGames(args) => self.search(args),
            ToolCall::GameDetails(args) => Ok(serde_json::to_value(self.game(&args.game_id)?)?),
            ToolCall::TranslationPatches(args) => self.patches(args, cancel),
        }
    }
}

pub fn definitions() -> Vec<rmcp::model::Tool> {
    use rmcp::model::{Tool, ToolAnnotations};
    [
        ("search_games", "Search the actual Lunchpail retail game catalog by title, platform, genre, and installed status. Read-only; returns stable game IDs.", schemars::schema_for!(SearchGames).to_value(), false),
        ("game_details", "Read catalog details for an exact game ID returned by search_games. No launch or filesystem access.", schemars::schema_for!(GameDetails).to_value(), false),
        ("translation_patches", "Find translation patch candidates for an exact catalog game. Uses archive/plaza/github provider lookups; never downloads or applies a patch. Coverage and ROM compatibility are explicitly qualified.", schemars::schema_for!(TranslationPatches).to_value(), true),
    ].into_iter().map(|(name, description, schema, open)| {
        Tool::new(name, description, schema.as_object().cloned().unwrap_or_default())
            .with_annotations(ToolAnnotations::new().read_only(true).destructive(false).idempotent(true).open_world(open))
    }).collect()
}

pub fn parse_call(name: &str, arguments: Value) -> Result<ToolCall> {
    serde_json::from_value(json!({"tool":name,"arguments":arguments}))
        .context("Invalid read-only tool request")
}

#[cfg(test)]
mod tests {
    use super::*;
    fn voice_catalog() -> Catalog {
        Catalog { games: [
            ("fax", "Faxanadu", "Nintendo Entertainment System", true),
            ("mario", "Super Mario Bros.", "Nintendo Entertainment System", false),
            ("metroid", "Metroid", "Nintendo Entertainment System", false),
            ("sequel", "Metroid II", "Nintendo Game Boy", false),
            ("castle", "Castlevania", "Nintendo Entertainment System", false),
        ].into_iter().map(|(id, title, platform, local)| crate::catalog::Game {
            id:id.into(), title:title.into(), platform:platform.into(), local, ..Default::default()
        }).collect(), ..Default::default() }
    }
    #[test]
    fn recovers_spoken_titles_from_catalog_not_the_unrelated_selection() {
        let catalog = voice_catalog();
        let context = TitleContext { selected_id: "mario".into(), ..Default::default() };
        for heard in ["facsinidu", "faxanadoo", "fax in a do"] {
            let result = match_game(&catalog, heard, "NES", &context);
            assert_eq!(result["match_kind"], "approximate", "{heard}: {result}");
            assert_eq!(result["auto_resolved"], true, "{heard}: {result}");
            assert_eq!(result["preferred_game_id"], "fax");
            assert_eq!(result["resolved_title"], "Faxanadu");
        }
        for (heard, platform) in [("facsinidu", "SNES"), ("Faxanadu 2", ""), ("unrelated gibberish", "")] {
            let result = match_game(&catalog, heard, platform, &context);
            assert_eq!(result["total_matches"], 0, "{heard}: {result}");
            assert_eq!(result["auto_resolved"], false);
        }
        assert_eq!(match_game(&catalog, "Super Mario Brothers", "", &context)["preferred_game_id"], "mario");
    }
    #[test]
    fn close_competing_titles_ask_once_and_exact_spelling_wins() {
        let mut catalog = voice_catalog();
        catalog.games.push(crate::catalog::Game { id:"near".into(), title:"Faksinadu".into(),
            platform:"Nintendo Entertainment System".into(), ..Default::default() });
        let context = TitleContext { selected_id:"fax".into(), recent_ids:vec!["fax".into()], ..Default::default() };
        let result = match_game(&catalog, "facsinidu", "NES", &context);
        assert_eq!(result["match_kind"], "ambiguous", "{result}");
        assert_eq!(result["auto_resolved"], false);
        assert!(result["preferred_game_id"].is_null());
        assert_eq!(result["games"].as_array().unwrap().len(), 2);
        assert_eq!(match_game(&catalog, "Faxanadu", "NES", &context)["preferred_game_id"], "fax");
        catalog.games[0].adult = true;
        catalog.games.last_mut().unwrap().non_retail = true;
        assert_eq!(match_game(&catalog, "facsinidu", "NES", &context)["total_matches"], 0);
    }
    #[test]
    fn prior_named_title_can_resolve_a_weaker_mishearing_but_selection_alone_cannot() {
        let mut catalog = voice_catalog();
        catalog.games.push(crate::catalog::Game { id:"other".into(), title:"Fascination".into(),
            platform:"Nintendo Entertainment System".into(), ..Default::default() });
        let mut context = TitleContext {selected_id:"fax".into(), ..Default::default()};
        assert_eq!(match_game(&catalog, "fascinado", "NES", &context)["auto_resolved"], false);
        context.utterances.push("I want to play Faxanadu for NES".into());
        let result = match_game(&catalog, "fascinado", "NES", &context);
        assert_eq!(result["auto_resolved"], true, "{result}");
        assert_eq!(result["preferred_game_id"], "fax");
    }
    #[test]
    fn vocabulary_is_bounded_deduplicated_and_uses_real_context() {
        let mut catalog = voice_catalog();
        catalog.games.push(catalog.games[0].clone());
        let context = TitleContext { selected_id:"mario".into(), recent_ids:vec!["fax".into()],
            utterances:vec!["I was talking about Castlevania".into()] };
        let titles = speech_titles(&catalog, &context, &[]);
        assert_eq!(titles, ["Super Mario Bros.", "Castlevania", "Faxanadu"]);
        assert_eq!(speech_titles(&catalog, &TitleContext::default(), &[]).len(), 0);
        assert_eq!(speech_titles(&catalog, &TitleContext::default(), &[2]), ["Metroid"]);
    }
    #[test]
    fn read_only_search_recovery_preserves_platform_and_owned_filters() {
        let context = ToolContext { catalog:Arc::new(voice_catalog()) };
        let result = context.search(&SearchGames { query:"facsinidu".into(), platform:"NES".into(),
            owned_only:true, limit:12, ..Default::default() }).unwrap();
        assert_eq!(result["resolution"]["auto_resolved"], true);
        assert_eq!(result["games"][0]["id"], "fax");
        let result = context.search(&SearchGames {query:"metrod".into(), owned_only:true, limit:12, ..Default::default()}).unwrap();
        assert_eq!(result["total_matches"], 0);
    }
    #[test]
    fn conversation_context_prioritizes_exact_spoken_titles_without_reordering_the_library() {
        use crate::catalog::Game;
        let mut catalog = Catalog::default();
        for number in 0..20 {
            catalog.games.push(Game { title:format!("New Super Mario Bros. edition {number}"), ..Game::default() });
        }
        catalog.games.push(Game {title:"Super Mario Bros.".into(), ..Game::default()});
        catalog.games.push(Game {title:"Super Mario Bros.".into(), platform:"Other platform".into(), ..Game::default()});
        catalog.games.push(Game {title:"Super Mario Bros. 2".into(), ..Game::default()});
        let indices: Vec<_> = (0..catalog.games.len()).collect();
        let sample = conversation_indices(&catalog, &indices, "SUPER MARIO BROTHERS");
        assert_eq!(sample.len(), 16);
        assert_eq!(&sample[..2], &[20, 21]); // Keep both exact matches; don't silently choose a platform.
        assert_eq!(&sample[2..], &(0..14).collect::<Vec<_>>());
        assert_eq!(indices, (0..23).collect::<Vec<_>>());
        assert_eq!(conversation_indices(&catalog, &indices, ""), (0..16).collect::<Vec<_>>());
        assert_ne!(spoken_title_key("brotherhood"), spoken_title_key("brothers"));
    }
    #[test]
    fn aliases_and_tool_boundaries() {
        assert!(platform_matches(
            "Super Nintendo Entertainment System",
            "SNES"
        ));
        assert!(!platform_matches("Nintendo Entertainment System", "SNES"));
        assert!(genre_matches("Role-Playing; Strategy", "JRPG"));
        assert!(parse_call("shell", json!({"command":"anything"})).is_err());
        assert!(parse_call("search_games", json!({"sql":"SELECT *"})).is_err());
        assert!(parse_call("game_details", json!({"game_id":"id","path":"/tmp"})).is_err());
        assert_eq!(definitions().len(), 3);
    }
    #[test]
    fn search_returns_real_ids_and_filters_unowned_and_hidden_games() {
        use crate::catalog::Game;
        let context = ToolContext {
            catalog: Arc::new(Catalog {
                games: vec![
                    Game {
                        id: "owned".into(),
                        title: "Alpha".into(),
                        platform: "Super Nintendo Entertainment System".into(),
                        local: true,
                        ..Game::default()
                    },
                    Game {
                        id: "adult".into(),
                        title: "Adult".into(),
                        local: true,
                        adult: true,
                        ..Game::default()
                    },
                    Game {
                        id: "remote".into(),
                        title: "Remote".into(),
                        ..Game::default()
                    },
                ],
                ..Catalog::default()
            }),
        };
        let result = context
            .search(&SearchGames {
                platform: "SNES".into(),
                owned_only: true,
                limit: 10,
                ..SearchGames::default()
            })
            .unwrap();
        assert_eq!(result["games"].as_array().unwrap().len(), 1);
        assert_eq!(result["games"][0]["id"], "owned");
        assert!(context.game("hallucinated-id").is_err());
        assert!(context.game("adult").is_err());
        assert!(
            context
                .search(&SearchGames {
                    limit: 999,
                    ..SearchGames::default()
                })
                .is_err()
        );
    }
    #[test]
    fn defaults_use_chronology_and_availability_but_respect_explicit_platforms() {
        use crate::list_view::{ListMetadataBuilder, MetadataInput};
        let mut catalog = Catalog::default();
        let mut metadata = ListMetadataBuilder::with_capacity(5);
        for (id, platform, year, date, local) in [
            ("port", "Commodore 64", Some(2019), None, true),
            ("coarse", "Arcade", Some(1985), None, false),
            ("original", "Nintendo Entertainment System", None, Some("1985-09-13"), false),
            ("disk", "Nintendo Famicom Disk System", None, Some("1986-02-21"), true),
            ("unknown", "Unknown", None, None, true),
        ] {
            catalog.games.push(crate::catalog::Game {id:id.into(), title:"Example Game".into(),
                platform:platform.into(), local, ..Default::default()});
            metadata.push(MetadataInput {release_year:year, release_date:date.map(str::to_owned), ..Default::default()}).unwrap();
        }
        catalog.list_metadata = metadata.finish();
        let result = resolve_game(&catalog, "Example Game", "");
        assert_eq!(result["preferred_game_id"], "original");
        assert_eq!(result["games"][0]["year"], 1985);
        assert_eq!(resolve_game(&catalog, "Example Game", "C64")["preferred_game_id"], "port");
        assert_eq!(resolve_game(&catalog, "Example Game", "n es")["preferred_game_id"], "original");
        assert_eq!(resolve_game(&catalog, "Example Game", "FDS")["preferred_game_id"], "disk");

        // Same chronology (or no chronology): prefer a copy already installed.
        catalog.list_metadata = Default::default();
        catalog.games[0].local = false;
        catalog.games[3].local = false;
        assert_eq!(resolve_game(&catalog, "Example Game", "")["preferred_game_id"], "unknown");
    }

    #[test]
    fn exact_resolution_ignores_selection_sequels_and_hidden_entries_and_keeps_ambiguity() {
        let mut catalog = Catalog::default();
        for (id, title, platform, adult, non_retail) in [
            ("fax", "Faxanadu", "Nintendo Entertainment System", false, false),
            ("mario", "Super Mario Bros.", "Nintendo Entertainment System", false, false),
            ("mario2", "Super Mario Bros. 2", "Nintendo Entertainment System", false, false),
            ("bundle", "Super Mario Bros. / Duck Hunt", "Nintendo Entertainment System", false, false),
            ("hidden", "Super Mario Bros.", "Nintendo Entertainment System", true, false),
            ("hack", "Super Mario Bros.", "Nintendo Entertainment System", false, true),
            ("other", "Super Mario Bros.", "Other Platform", false, false),
        ] {
            catalog.games.push(crate::catalog::Game {id:id.into(),title:title.into(),platform:platform.into(),adult,non_retail,..Default::default()});
        }
        let all = resolve_game(&catalog, "Super Mario Brothers", "");
        assert_eq!(all["total_matches"], 2);
        assert_eq!(all["games"][0]["id"], "mario");
        let nes = resolve_game(&catalog, "super mario brothers", "NES");
        assert_eq!(nes["total_matches"], 1);
        assert_eq!(nes["games"][0]["id"], "mario");
        assert_eq!(resolve_game(&catalog, "Super Mario", "")["total_matches"], 0);
        for index in 0..25 {
            catalog.games.push(crate::catalog::Game {id:format!("duplicate-{index}"),title:"Super Mario Bros.".into(),..Default::default()});
        }
        let many = resolve_game(&catalog, "Super Mario Brothers", "");
        assert_eq!(many["total_matches"], 27);
        assert_eq!(many["games"].as_array().unwrap().len(), 20);
    }
    #[test]
    fn read_only_search_matches_spoken_and_literal_brothers() {
        let context = ToolContext {catalog: Arc::new(Catalog {games: vec![
            crate::catalog::Game {id:"mario".into(),title:"Super Mario Bros.".into(),..Default::default()},
            crate::catalog::Game {id:"arms".into(),title:"Brothers in Arms".into(),..Default::default()},
        ],..Default::default()})};
        for (query, expected) in [("SUPER MARIO BROTHERS", "mario"), ("Brothers in Arms", "arms"), ("Bros. in Arms", "arms")] {
            let result = context.search(&SearchGames {query:query.into(),limit:12,..Default::default()}).unwrap();
            assert_eq!(result["total_matches"], 1);
            assert_eq!(result["games"][0]["id"], expected);
        }
    }
}
