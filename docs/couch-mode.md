# Couch Mode

Couch Mode is a fullscreen way to browse the same library with a controller,
keyboard, or mouse. Open it from the main window's Couch Mode control.

![Lunchpail in Couch Mode](images/couch-mode.png)

## Choose a view

| View | Best for |
| --- | --- |
| Cover wall | Seeing many covers at once. |
| Cover flow | Browsing angled covers around a prominent selected game. |
| Logo wheel | A curved, animated list of game logos beside a video preview. Missing logos use readable titles. |
| Cover shelf | A horizontal cover row with stable spacing and a selected-game preview. |

Use the view button, **Library & settings**, or the Couch Mode section in
Settings. Press **Ctrl+V** to cycle views from the keyboard.

Lunchpail remembers the view and keeps the selected game when you switch.

## Browse and play

Choose a shelf such as My Collection, Favorites, or Recent. The platform and
collection pickers narrow the same library used by normal mode.

Use up/down through the wheel, left/right through cover flow or the shelf, and
both directions through the wall. Select a game to see its actions, then choose
Play or download options.

The Game Menu includes favorite, release, view, and attract-mode choices.

## Search with a keyboard or microphone

Start typing while browsing to open the large search panel. **F3** or the Search
button opens the current query. Results update in the current shelf/platform;
Enter or Escape returns to those results. Back once more clears the query before
leaving Couch Mode. The Game Menu's **Search games · voice or keyboard** action
opens the same panel with a controller. In the panel, the D-pad selects the mic,
clear, or browse button, and the south face button activates it.

**F2** or the Mic button offers a one-time **191 MB English model download** from
the model publisher on Hugging Face. This setup step does not open the microphone.
After setup, activate **Speak** to capture from the system's default microphone.
Local sherpa-onnx recognition updates the editable query while you speak. Capture
stops at a speech pause, after 15 seconds, when you press Stop, or when you leave
the panel. Typing cancels voice input so late results cannot replace your edits.
Audio is never saved or uploaded. A network connection is only needed for model
setup; recognition then works offline. Voice search never installs or launches a
game. Search accepts spoken “Brothers” for titles written “Bros.” while keeping
literal matches too. Unusual game titles may need a keyboard correction.

Navigation uses quiet movement, confirm, and back sounds. Their saved toggle and
volume are in **Settings → Couch Mode**, separately from video and music settings.
While the microphone is active, navigation sounds and preview audio are silenced
without changing the shared video mute preference or the music's paused state.

The recognizer is [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), Apache-2.0,
with the Apache-2.0 [English streaming Zipformer model](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-21).
Model files are revision-pinned and SHA-256 checked before use, and stored in the
application data directory under `speech/zipformer-en-2023-06-21`. To choose another
microphone, change your operating system's default input device before starting
voice search.

## Game details and tools

**Game details & tools** opens a full-screen page with five tabs: Overview,
Play & setup, Media, Activity, and Library. A large green **Install / Play** button
stays at the top of every tab and is the default controller action. **Install**
opens the version and download review before anything is queued; installed games
show **Play** when ready. If setup is needed, the button opens launch settings.
Downloads in progress show installation status and open the queue, including
paused or failed installs. Favorites and other releases stay beside the cover.
Use the bumpers to switch tabs, then the D-pad to choose a tool.

![Full-screen game details in Couch Mode](images/couch-game-details.png)

Play & setup includes display settings, controller mappings, patches and cheats,
RetroAchievements, ROM choices, and save locations. **Emulator & launch** includes
runtime selection, game/system defaults, launch profiles, BIOS setup, GameBuddy,
and PC installation preparation. Management sections stay in a full-screen game
page with a persistent section rail; they do not open the normal details sidebar.

Overview includes available release, developer, publisher, genre, player, region,
series, age-rating, and catalog-rating information. Activity includes completion,
notes, and session history. Library provides metadata editing, collection
membership, related games, custom fields, tags, and external catalog links.

**Library & settings** opens settings, downloads, notifications, imports,
collections, firmware, media tools, and bulk editing. The full library
workspace is available for search, sorting, and organization.

Use **Back to Couch Mode** to return from that workspace without losing the
selected game.

Focused editors such as metadata, controller mapping, and launch profiles still
use shared dialogs above the game page. Text entry and
native file pickers may need a keyboard or mouse; not every workflow is a
controller-only, TV-sized interface yet.

## Wheel logos

The wheel uses transparent game-title images, usually called **clear logos**
or **wheel logos**. Lunchpail checks your configured artwork providers for
the actual logo rather than substituting a box cover. EmuMovies and ScreenScraper
are useful sources; connect them in Settings. Coverage varies by game and release.

If a logo is missing or incorrect, open **Media → Find better media** to choose
another image. Until a logo is available, the wheel shows the game's title.

![Game logo wheel with an animated HyperSpin video theme](images/couch-logo-wheel.png)

## HyperSpin video themes and system media

Open **Media → Themes & system media** (or **Themes & systems** in the section rail) to
find a pre-rendered HyperSpin game theme, a system wheel logo, or a platform video
through your connected EmuMovies account. Theme videos require FTP access from a
supporting EmuMovies account. Availability varies by system and game.

Game themes are stored separately from gameplay videos. The logo wheel and cover
shelf prefer a cached theme and otherwise play the cached gameplay clip; browsing
does not download video packs. Previews preserve aspect ratio, can be paused or
opened full-screen, and share the global video mute preference. Background music
stops while an audible preview is playing. Opening another page suspends previews.

The platform picker displays cached system logos and platform videos. These use
a separate system-media cache, never a game's box art or logo slot.

![Platform wheel artwork and video presentation](images/couch-platform-media.png)

This supports the [pre-rendered themes published by EmuMovies](https://emumovies.com/files/category/2031-video-themes/),
not execution of raw HyperSpin theme packages. EmuMovies also publishes
[system and game logo artwork](https://emumovies.com/files/category/1196-artwork/).

## Useful controls

- D-pad or left stick: move.
- South face button: select.
- East face button: back or close the current panel.
- Bumpers: page through the focused list.
- **F3**: search. **F2**: voice search/setup.
- **Ctrl+F**: favorite. **Ctrl+D**: details. **Ctrl+M**: game menu.
- **Ctrl+O**: Library & settings. **Ctrl+V**: change view.
- **Ctrl+A**: attract mode. **Ctrl+P**: pause/resume background music.

When a dialog is open, controller navigation stays with that dialog rather
than moving the game list behind it.

## Attract mode, music, and themes

Attract mode tours games from the current shelf. Start it from the Game Menu
or choose an idle delay in Settings.

Background game music is optional and uses available cached media. You can
adjust or mute it in the Couch Mode settings.

See [Themes](themes.md) to change colors and background artwork.
