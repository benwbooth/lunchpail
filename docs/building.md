# Build Lunchpail from source

Most users should use a [release package](installing.md). Building from source
is useful if you want to try a change before the next release or contribute a fix.

## Build with Nix

Clone the repository and run:

~~~sh
git clone https://github.com/benwbooth/lunchpail.git
cd lunchpail
nix build .#lunchpail
./result/bin/lunchpail
~~~

The build uses the versions pinned by the repository. The first build may
download and compile substantial dependencies.

## Work on the app

From the repository root, run:

~~~sh
./dev.sh
~~~

The script enters the development environment when needed, watches source
changes, rebuilds, and relaunches Lunchpail. Leave one watcher running rather
than starting another after every edit.

Development restarts hand off the UI without terminating a running emulator.
The replacement UI adopts the existing game; the original process remains a
background session host only until that game finishes, keeping calibrated
controllers, GameBuddy, and launch resources alive. Save-exit notifications and
automatic backup are handed to the replacement UI. If the running build cannot
acknowledge a safe handoff, the watcher defers the restart instead of killing it.
When upgrading from an older build without this protocol, close the old UI after
finishing your game and start `./dev.sh` again once.

Do not use this workflow against an irreplaceable profile without a backup.
For a separate writable profile, the app supports
`--state-database /path/to/test-state.db`. That isolates Lunchpail's profile,
not every external emulator or service you might launch.

## Other build environments

The repository's [package workflow](../.github/workflows/native-packages.yml)
contains the current Windows, macOS, AppImage, and Flatpak build steps.
The [flake](../flake.nix) defines the Nix environment.

For Windows source builds, Qt uses the dynamic MSVC C runtime (`/MD`). Before
running Cargo, extract the pinned `win-x64-static-MD-Release-lib` Sherpa archive
listed in the package workflow and set `SHERPA_ONNX_LIB_DIR` to its `lib` folder.
The Rust crate's automatic `/MT` archive does not link compatibly with Qt. This
is a build-time requirement only; the packaged app needs no Sherpa installation.

Build the bundled assistant/Whisper workers with
`python3 packaging/build-inference.py` (`python` on Windows). The script builds
independent CPU and GPU runtimes; native packages and `dev.sh` run it automatically.
See [local AI setup](couch-mode.md#local-assistant-setup) for device support.

An app that builds successfully may still need platform-specific packaging,
multimedia plugins, and GPU support. In particular, do not assume a custom
build includes live-translation acceleration just because the main UI opens.

OCR loads its GPU-capable ONNX Runtime dynamically, independently of the static
CPU runtime used by Couch Mode speech search. Nix supplies `ORT_DYLIB_PATH`;
Flatpak supplies the runtime in `/app/lib`. For native source builds, stage the
pinned runtime next to the executable before using translation:

~~~sh
# Windows x86-64
python packaging/stage-ocr-runtime.py windows-x86_64 --runtime-dir target/release --licenses-dir target/release/licenses
# Apple Silicon macOS
python3 packaging/stage-ocr-runtime.py macos-arm64 --runtime-dir target/release --licenses-dir target/release/licenses
~~~

The package workflow runs these staging steps automatically. The optional
`couch_speech::tests::real_model_transcribes_fixture` test accepts
`LUNCHPAIL_SPEECH_TEST_WAV` and `LUNCHPAIL_SPEECH_EXPECT`. Set
`LUNCHPAIL_SPEECH_TEST_GPU_OCR=1` to also initialize and warm installed GPU OCR
models in the same process before transcribing; the test never opens a microphone.

## Contribute

Keep changes focused and describe how you tested the behavior. For a visual
change, a screenshot helps reviewers understand it.

For normal use, return to the [user guide](README.md).
