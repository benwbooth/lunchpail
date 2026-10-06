//! One typed capability catalog for local models, HTTP providers and MCP.
//! All mutations are dispatched on the GUI thread through existing workflows.
use crate::assistant_tools::{GameDetails, SearchGames, TranslationPatches};
use anyhow::{Context, Result, ensure};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Empty {}
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema)]
#[serde(default, deny_unknown_fields)]
pub struct Browse {
    /// Title words only, or empty to clear the search.
    pub query: String,
    /// Canonical platform name, or empty for all platforms.
    pub platform: String,
    /// all, local, downloadable, favorites, or recent.
    pub shelf: String,
    /// Exact ID from get_collections; when set, browse this collection instead of a shelf.
    pub collection_id: String,
}
#[derive(Clone, Debug, Default, Deserialize, Serialize, JsonSchema)]
#[serde(default, deny_unknown_fields)]
pub struct GameRef {
    /// Exact catalog ID, or empty to use the currently selected game.
    pub game_id: String,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Favorite {
    #[serde(default)]
    pub game_id: String,
    pub favorite: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Named {
    pub name: String,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Preference {
    pub name: String,
    #[schemars(schema_with = "preference_value_schema")]
    pub value: Value,
}
fn preference_value_schema(_: &mut schemars::SchemaGenerator) -> schemars::Schema {
    // Boolean JSON schemas are legal, but Ollama's ToolProperty decoder only
    // accepts objects. These are exactly the scalar types our validator allows.
    schemars::json_schema!({"type": ["boolean", "number", "string"]})
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Collection {
    #[serde(default)]
    pub collection_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Membership {
    pub collection_id: String,
    #[serde(default)]
    pub game_id: String,
    pub included: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Confirmation {
    pub approve: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Reply {
    pub message: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(
    tag = "tool",
    content = "arguments",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum Call {
    GetContext(Empty),
    SearchGames(SearchGames),
    GameDetails(GameDetails),
    TranslationPatches(TranslationPatches),
    BrowseLibrary(Browse),
    SelectGame(GameRef),
    PlayGame(GameRef),
    StopGame(Empty),
    Navigate(Named),
    OpenSettings(Named),
    OpenPanel(Named),
    OpenGameTool(Named),
    ControlMedia(Named),
    SetFavorite(Favorite),
    GetPreferences(Empty),
    SetPreference(Preference),
    GetCollections(Empty),
    SaveCollection(Collection),
    DeleteCollection(Collection),
    SetCollectionMembership(Membership),
    ConfirmAction(Confirmation),
    Answer(Reply),
}

pub const NAVIGATION: &[&str] = &[
    "up",
    "down",
    "left",
    "right",
    "back",
    "details",
    "menu",
    "platforms",
    "collections",
    "normal_mode",
    "couch_mode",
];
pub const SETTINGS: &[&str] = &[
    "general",
    "local-ai",
    "controllers",
    "emulators",
    "achievements",
    "translation",
    "savecloud",
    "qbittorrent",
    "emumovies",
    "steamgriddb",
    "screenscraper",
    "igdb",
];
pub const PANELS: &[&str] = &[
    "details",
    "library",
    "settings",
    "controllers",
    "downloads",
    "notifications",
    "import",
    "torrent",
    "collections",
    "new-collection",
    "firmware",
    "media",
    "audit",
    "bulk",
    "attract",
];
pub const GAME_TOOLS: &[&str] = &[
    "controllers",
    "box3d",
    "find-media",
    "video",
    "theme-video",
    "sessions",
    "metadata",
    "emulators",
    "launch-profile",
    "firmware",
    "emumovies",
    "new-collection",
    "display",
    "mods",
    "achievements",
    "files",
    "launch",
    "artwork",
    "media",
    "themes",
    "activity",
    "collections",
    "related",
    "catalog",
];
pub const MEDIA: &[&str] = &[
    "play",
    "pause",
    "mute",
    "unmute",
    "fullscreen",
    "close_fullscreen",
];
pub const PREFERENCES: &[&str] = &[
    "view_style",
    "video_muted",
    "navigation_sounds",
    "navigation_volume",
    "music_enabled",
    "music_volume",
    "spoken_replies",
    "captions",
    "wake_word",
    "hands_free",
    "voice_rate",
    "voice_volume",
];

pub fn parse(name: &str, arguments: Value) -> Result<Call> {
    ensure!(
        arguments.to_string().len() <= 8192,
        "Tool arguments are too large"
    );
    let call: Call = serde_json::from_value(json!({"tool":name,"arguments":arguments}))
        .context("Unknown tool or invalid arguments")?;
    let named = match &call {
        Call::Navigate(a) => Some((&a.name, NAVIGATION)),
        Call::OpenSettings(a) => Some((&a.name, SETTINGS)),
        Call::OpenPanel(a) => Some((&a.name, PANELS)),
        Call::OpenGameTool(a) => Some((&a.name, GAME_TOOLS)),
        Call::ControlMedia(a) => Some((&a.name, MEDIA)),
        Call::SetPreference(a) => Some((&a.name, PREFERENCES)),
        _ => None,
    };
    if let Some((name, choices)) = named {
        ensure!(
            choices.contains(&name.as_str()),
            "Unsupported action: {name}"
        );
    }
    match &call {
        Call::BrowseLibrary(a) => {
            ensure!(
                a.query.len() <= 160 && a.platform.len() <= 100 && a.collection_id.len() <= 200,
                "Search is too long"
            );
            ensure!(
                ["", "all", "local", "downloadable", "favorites", "recent"]
                    .contains(&a.shelf.as_str()),
                "Unknown shelf"
            );
        }
        Call::SetPreference(a) => match a.name.as_str() {
            "view_style" => ensure!(
                a.value
                    .as_str()
                    .is_some_and(|v| ["wheel", "shelf", "wall", "album", "grid", "list"].contains(&v)),
                "Unknown view style"
            ),
            "navigation_volume" | "voice_volume" => ensure!(
                a.value.as_f64().is_some_and(|v| (0.0..=1.0).contains(&v)),
                "Volume must be between 0 and 1"
            ),
            "music_volume" => ensure!(
                a.value.as_u64().is_some_and(|v| v <= 100),
                "Music volume must be between 0 and 100"
            ),
            "voice_rate" => ensure!(
                a.value.as_f64().is_some_and(|v| (-1.0..=1.0).contains(&v)),
                "Rate must be between -1 and 1"
            ),
            _ => ensure!(a.value.is_boolean(), "This preference needs true or false"),
        },
        Call::SaveCollection(a) | Call::DeleteCollection(a) => ensure!(
            a.collection_id.len() <= 200 && a.name.len() <= 120 && a.description.len() <= 2000,
            "Collection fields are too long"
        ),
        Call::Answer(a) => ensure!(
            !a.message.trim().is_empty() && a.message.len() <= 6000,
            "Reply is empty or too long"
        ),
        _ => (),
    }
    Ok(call)
}

pub fn definitions() -> Vec<rmcp::model::Tool> {
    use rmcp::model::{Tool, ToolAnnotations};
    let mut tools = crate::assistant_tools::definitions();
    let mut add = |name: &'static str,
                   description: &'static str,
                   mut schema: Value,
                   choices: &[&str],
                   read: bool,
                   destructive: bool| {
        if !choices.is_empty() {
            schema["properties"]["name"]["enum"] = json!(choices);
        }
        tools.push(
            Tool::new(
                name,
                description,
                schema.as_object().cloned().unwrap_or_default(),
            )
            .with_annotations(
                ToolAnnotations::new()
                    .read_only(read)
                    .destructive(destructive)
                    .open_world(false),
            ),
        );
    };
    add(
        "get_context",
        "Read the current screen, selected game, visible results, running game and any pending confirmation. Call before acting on 'this game', 'it', or 'play the game'.",
        schemars::schema_for!(Empty).to_value(),
        &[],
        true,
        false,
    );
    add(
        "browse_library",
        "Show a title search/platform/shelf in the real browser. query is title words only. Returns actual filtered results after the UI updates. Does not launch anything.",
        schemars::schema_for!(Browse).to_value(),
        &[],
        false,
        false,
    );
    add(
        "select_game",
        "Select one exact catalog game ID, changing the visible platform/filter if necessary. Empty ID keeps the current selection.",
        schemars::schema_for!(GameRef).to_value(),
        &[],
        false,
        false,
    );
    add(
        "play_game",
        "Launch the requested exact game, or the current selection for an empty ID, through Lunchpail's normal save/resume/launch workflow. Use only when the user asks to play. Report success only if the result says running; missing games may require download/setup.",
        schemars::schema_for!(GameRef).to_value(),
        &[],
        false,
        false,
    );
    add(
        "stop_game",
        "Request to stop the running game through the normal save/exit workflow. Requires the user's confirmation on a subsequent turn.",
        schemars::schema_for!(Empty).to_value(),
        &[],
        false,
        true,
    );
    add(
        "navigate",
        "Move focus or open the requested navigation surface. Does not synthesize arbitrary key presses.",
        schemars::schema_for!(Named).to_value(),
        NAVIGATION,
        false,
        false,
    );
    add(
        "open_settings",
        "Open an exact settings section for setup. Credentials are entered privately in the UI; never ask the user to dictate a password/API key.",
        schemars::schema_for!(Named).to_value(),
        SETTINGS,
        false,
        false,
    );
    add(
        "open_panel",
        "Open a library-management workflow, download queue, audit, import, collections, notifications, or other named tool. Opening a workflow does not complete it.",
        schemars::schema_for!(Named).to_value(),
        PANELS,
        false,
        false,
    );
    add(
        "open_game_tool",
        "Open the selected game's settings/workflow (emulators, launch profiles, display, mods, files, metadata, media, achievements, etc.). Existing UI confirmations remain in force. Report that the panel was opened, not that installation/setup finished.",
        schemars::schema_for!(Named).to_value(),
        GAME_TOOLS,
        false,
        false,
    );
    add(
        "control_media",
        "Control the current preview, its shared mode-specific audio, or fullscreen video. Never changes game audio.",
        schemars::schema_for!(Named).to_value(),
        MEDIA,
        false,
        false,
    );
    add(
        "set_favorite",
        "Set a game's favorite status. Empty ID means the current selection; waits for saved state.",
        schemars::schema_for!(Favorite).to_value(),
        &[],
        false,
        false,
    );
    add(
        "get_preferences",
        "Read non-sensitive display, preview audio, voice and caption preferences. Never returns credentials.",
        schemars::schema_for!(Empty).to_value(),
        &[],
        true,
        false,
    );
    add(
        "set_preference",
        "Save a listed preference. view_style is grid/list in normal mode or wheel/shelf/wall/album in Couch mode; video_muted affects only the current mode. Music and navigation sounds are Couch preferences. navigation_volume and voice_volume are 0..1; voice_rate -1..1; music_volume 0..100; others boolean. Enabling hands_free in both modes requires subsequent user confirmation.",
        schemars::schema_for!(Preference).to_value(),
        PREFERENCES,
        false,
        false,
    );
    add(
        "get_collections",
        "List actual collections and their stable IDs.",
        schemars::schema_for!(Empty).to_value(),
        &[],
        true,
        false,
    );
    add(
        "save_collection",
        "Create a collection (empty collection_id) or update an existing collection's name and description. Does not change membership.",
        schemars::schema_for!(Collection).to_value(),
        &[],
        false,
        false,
    );
    add(
        "delete_collection",
        "Request deletion of an exact collection. Games are retained. Requires user confirmation on a later turn.",
        schemars::schema_for!(Collection).to_value(),
        &[],
        false,
        true,
    );
    add(
        "set_collection_membership",
        "Add/remove a game in an existing collection. Empty game_id means the selected game.",
        schemars::schema_for!(Membership).to_value(),
        &[],
        false,
        false,
    );
    add(
        "confirm_action",
        "Approve or decline the pending action ONLY after the user explicitly answers its confirmation question. Cannot confirm an action requested in the same turn.",
        schemars::schema_for!(Confirmation).to_value(),
        &[],
        false,
        false,
    );
    tools
}

pub fn local_schema(final_only: bool) -> Value {
    let mut schema = schemars::schema_for!(Call).to_value();
    // The native grammar emits object properties in sorted order. An adjacent
    // tag therefore forces `arguments` BEFORE `tool`, making a small model pick
    // an argument shape (often an echoed answer) before it can choose an action.
    // A single tool-name key makes the action the first generated decision.
    let variants = schema["oneOf"].as_array().expect("Call is a tagged enum");
    let variants: Vec<_> = variants.iter().filter_map(|variant| {
        let name = variant["properties"]["tool"]["const"].as_str()?;
        if final_only && name != "answer" { return None; }
        Some(json!({
            "type":"object", "additionalProperties":false,
            "properties":{name:variant["properties"]["arguments"].clone()},
            "required":[name],
        }))
    }).collect();
    schema["oneOf"] = json!(variants);
    schema
}

pub fn parse_local(value: Value) -> Result<(String, Value, Call)> {
    let object = value.as_object().context("Local reply must be a tool object")?;
    ensure!(object.len() == 1, "Local reply must contain exactly one tool");
    let (name, arguments) = object.iter().next().unwrap();
    let call = parse(name, arguments.clone())?;
    Ok((name.clone(), arguments.clone(), call))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn local_grammar_chooses_the_action_before_its_arguments() {
        let schema = local_schema(false);
        let variants = schema["oneOf"].as_array().unwrap();
        assert_eq!(variants.len(), 22);
        for variant in variants {
            let properties = variant["properties"].as_object().unwrap();
            assert_eq!(properties.len(), 1);
            let name = properties.keys().next().unwrap();
            assert_eq!(variant["required"], json!([name]));
            assert_ne!(name, "arguments");
        }
        assert!(schema["$defs"]["Reply"].is_object());
        let (name, arguments, call) = parse_local(json!({"play_game":{"game_id":"mario"}})).unwrap();
        assert_eq!(name, "play_game");
        assert_eq!(arguments, json!({"game_id":"mario"}));
        assert!(matches!(call, Call::PlayGame(_)));
        for invalid in [json!({}), json!({"tool":"answer","arguments":{"message":"echo"}}),
            json!({"get_context":{},"play_game":{}}), json!({"shell":{"command":"no"}})] {
            assert!(parse_local(invalid).is_err());
        }
    }
    #[test]
    fn local_final_turn_can_only_answer() {
        let schema = local_schema(true);
        let variants = schema["oneOf"].as_array().unwrap();
        assert_eq!(variants.len(), 1);
        assert_eq!(variants[0]["required"], json!(["answer"]));
        assert!(matches!(parse_local(json!({"answer":{"message":"Ready"}})).unwrap().2, Call::Answer(_)));
    }
    #[test]
    fn capability_boundaries_reject_code_paths_and_invalid_preferences() {
        for (name, args) in [
            ("shell", json!({"command":"anything"})),
            ("play_game", json!({"game_id":"x","command":"x"})),
            ("open_settings", json!({"name":"../../secrets"})),
            ("set_preference", json!({"name":"api_key","value":"secret"})),
            (
                "set_preference",
                json!({"name":"video_muted","value":"false"}),
            ),
            ("set_preference", json!({"name":"voice_volume","value":5})),
        ] {
            assert!(parse(name, args).is_err(), "{name}");
        }
        assert!(parse("play_game", json!({})).is_ok());
        assert!(parse("set_preference", json!({"name":"captions","value":false})).is_ok());
        for style in ["grid", "list", "wheel", "shelf", "wall", "album"] {
            assert!(parse("set_preference", json!({"name":"view_style","value":style})).is_ok());
        }
        assert!(parse("set_preference", json!({"name":"view_style","value":"desktop"})).is_err());
        assert_eq!(definitions().len(), 21);
    }
}
