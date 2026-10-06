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
    title.to_lowercase().split(|c: char| !c.is_alphanumeric())
        .map(|word| if word == "brothers" { "bros" } else { word }).collect()
}

/// Resolve against the already-loaded catalog, not the selected game or a
/// truncated search sample. Keep the full count so ambiguity cannot disappear.
pub(crate) fn resolve_game(catalog: &Catalog, title: &str, platform: &str) -> Value {
    let title = spoken_title_key(title);
    let matches: Vec<_> = catalog.games.iter().filter(|game| {
        !title.is_empty() && !game.adult && !game.non_retail
            && platform_matches(&game.platform, platform)
            && spoken_title_key(&game.title) == title
    }).collect();
    let rows: Vec<_> = matches.iter().take(20).map(|game| json!({
        "id":game.id,"title":game.title,"platform":game.platform,
        "local":game.local,"downloadable":game.downloadable,
    })).collect();
    json!({"games":rows,"total_matches":matches.len()})
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
            json!({"games":cards,"total_matches":total,"note":"Ratings are catalog metadata, not a guarantee. JRPG maps to Role-Playing; region/origin is not inferred. Adult and non-retail entries are excluded."}),
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
            let result = context.search(&SearchGames {query:query.into(),..Default::default()}).unwrap();
            assert_eq!(result["total_matches"], 1);
            assert_eq!(result["games"][0]["id"], expected);
        }
    }
}
