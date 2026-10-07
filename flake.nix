{
  description = "Lunchpail canonical game database and native frontend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Current Eden AppImages use DwarFS. Keep its NixOS extraction tool on a
    # known-good nixpkgs revision while the primary rolling input advances.
    nixpkgs-dwarfs.url = "github:NixOS/nixpkgs/a5cc6f2c37bf518436dc8d1c288ccd0c43c2f4c4";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-dwarfs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        onnxruntimeRocm = pkgs.onnxruntime.override { rocmSupport = true; };
        onnxruntimeForHost = if system == "x86_64-linux" then onnxruntimeRocm else pkgs.onnxruntime;
        dwarfsPkgs = import nixpkgs-dwarfs { inherit system; };
        dwarfs = dwarfsPkgs.dwarfs;
        sherpaArchives = {
          x86_64-linux = { target = "linux-x64"; sha256 = "e1fdc5b67530e15741ef897fa5ffff297056f3bf0c6d829a27af9225a4c4b5a6"; };
          aarch64-linux = { target = "linux-aarch64"; sha256 = "77983e3cf29aa60f2e531d249dbd01d15596530550c8db2e9e02fc6a655da6bb"; };
          aarch64-darwin = { target = "osx-arm64"; sha256 = "9091bf160dc7fdacedbc906b212badf53c2993f4e5277a0e03998e96c31d60da"; };
        };
        sherpaArchive = pkgs.fetchurl {
          url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-${sherpaArchives.${system}.target}-static-lib.tar.bz2";
          inherit (sherpaArchives.${system}) sha256;
        };
        sherpaLibraries = pkgs.runCommand "sherpa-onnx-1.13.8-static" { nativeBuildInputs = [ pkgs.bzip2 ]; } ''
          mkdir -p $out
          tar -xjf ${sherpaArchive} -C $out --strip-components=1
        '';
        # MAME's CHD core, linked so compressed disc images (CHD) work on every
        # host without a chdman install. libchdman-rs ships its static archives
        # as release assets; the URLs and hashes below are the pinned inputs,
        # and build.rs links whichever one matches the target triple.
        chdmanArchives = {
          x86_64-linux = {
            name = "libchdman_rs-x86_64-unknown-linux-gnu-glibc2.35.a";
            hash = "sha256-U0D05l0P0MQNWx3Txq0dXaplPdt/k6/7cPBIDLx4Ghc=";
          };
          aarch64-linux = {
            name = "libchdman_rs-aarch64-unknown-linux-gnu-glibc2.35.a";
            hash = "sha256-Xh5Y9nl4goWdvHhFFhIOdA4XhTm4GALTY4OJTNNH7Gw=";
          };
          aarch64-darwin = {
            name = "libchdman_rs-aarch64-apple-darwin.a";
            hash = "sha256-vLumhaclyOhG0zS/pt6To+4rHevQUtVWW856UBz+i+g=";
          };
        };
        chdmanArchive = pkgs.fetchurl {
          url = "https://github.com/danifunker/libchdman-rs/releases/download/v0.289.0/${chdmanArchives.${system}.name}";
          hash = chdmanArchives.${system}.hash;
        };
        # Qt 6.11's Flite discovery accidentally reads an empty environment.
        # Without this correction it ignores LD_LIBRARY_PATH and cannot find
        # Nix's voice libraries (there is deliberately no /usr/lib fallback).
        qtSpeech = if pkgs.stdenv.hostPlatform.isLinux then pkgs.qt6.qtspeech.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace src/plugins/tts/flite/qtexttospeech_flite_processor.cpp \
              --replace-warn 'const QProcessEnvironment pe;' 'const auto pe = QProcessEnvironment::systemEnvironment();'
          '';
        }) else pkgs.qt6.qtspeech;
        qtModules = with pkgs.qt6; [
          qtbase
          qtdeclarative
          qtimageformats
          qtmultimedia
          qtquick3d
          qtSpeech
          qtsvg
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          qtwayland
          # The desktop Quick Controls style follows KDE's active widget
          # theme and color scheme instead of Qt's generic Linux Fusion style.
          pkgs.kdePackages.qqc2-desktop-style
        ];
        qtEnv = pkgs.qt6.env "lunchpail-qt-env" qtModules;
        workspaceVersion = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).workspace.package.version;
        databaseTool = pkgs.rustPlatform.buildRustPackage {
          pname = "lunchpail-db";
          version = workspaceVersion;
          src = pkgs.lib.cleanSource ./.;
          cargoLock.lockFile = ./Cargo.lock;
          LUNCHPAIL_7Z = "${pkgs.p7zip}/bin/7z";
          # Link the pinned MAME CHD archive instead of compiling MAME or
          # downloading an asset inside the sandbox.
          LIBCHDMAN_PREBUILT_LOCAL_ARCHIVE = "${chdmanArchive}";
          cargoBuildFlags = [ "--package" "lunchpail-db" ];
          cargoTestFlags = [ "--package" "lunchpail-db" ];
        };
        controllerProbe = pkgs.rustPlatform.buildRustPackage {
          pname = "lunchpail-controller-probe";
          version = workspaceVersion;
          src = pkgs.lib.cleanSource ./.;
          cargoLock.lockFile = ./Cargo.lock;
          cargoBuildFlags = [ "--package" "lunchpail-controller-probe" ];
          cargoTestFlags = [ "--package" "lunchpail-controller-probe" ];
          meta = with pkgs.lib; {
            description = "Target-runtime SDL3 controller inventory for Lunchpail adapters";
            license = licenses.mit;
            mainProgram = "lunchpail-controller-probe";
            platforms = platforms.linux ++ platforms.darwin;
          };
        };
        frontend = pkgs.rustPlatform.buildRustPackage {
          pname = "lunchpail";
          version = workspaceVersion;
          src = pkgs.lib.cleanSource ./.;
          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            p7zip
            pkg-config
            rustPlatform.bindgenHook
            python3
            qt6.wrapQtAppsHook
          ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.shaderc ];
          buildInputs = qtModules ++ [ onnxruntimeForHost ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            dwarfs
            pkgs.systemd
            pkgs.alsa-lib
            pkgs.spirv-headers
            pkgs.vulkan-headers
            pkgs.vulkan-loader
          ];
          SHERPA_ONNX_LIB_DIR = "${sherpaLibraries}/lib";
          dontUseCmakeConfigure = true;
          dontUseNinjaBuild = true;
          dontUseNinjaInstall = true;
          QMAKE = "${qtEnv}/bin/qmake";
          ORT_LIB_PATH = "${onnxruntimeForHost}/lib";
          ORT_DYLIB_PATH = "${onnxruntimeForHost}/lib/${if pkgs.stdenv.hostPlatform.isDarwin then "libonnxruntime.dylib" else "libonnxruntime.so"}";
          ORT_PREFER_DYNAMIC_LINK = "1";
          LIBCHDMAN_PREBUILT_LOCAL_ARCHIVE = "${chdmanArchive}";
          LUNCHPAIL_SDL3_LIBRARY = "${pkgs.lib.getLib pkgs.sdl3}/lib/${if pkgs.stdenv.hostPlatform.isDarwin then "libSDL3.dylib" else "libSDL3.so.0"}";
          # Release builds embed the exact flake revision for the UI build
          # label; the build time is stamped in preBuild.
          LUNCHPAIL_BUILD_HASH = self.shortRev or self.dirtyShortRev or "";
          preBuild = ''
            export PATH="${qtEnv}/bin:${qtEnv}/libexec:$PATH"
            export QMAKE="${qtEnv}/bin/qmake"
            export QT_INCLUDE_PATH="${qtEnv}/include"
            export QT_LIBEXEC_PATH="${qtEnv}/libexec"
            # Stamp the real build time into the binary for the window's build
            # label. Nix caches by derivation, so an unchanged input keeps the
            # existing build; a source change produces the new timestamp.
            export LUNCHPAIL_BUILT_UNIX="$(date +%s)"
          '';
          cargoBuildFlags = [ "--package" "lunchpail-app" "--package" "lunchpail-controller-probe" "--bin" "lunchpail" "--bin" "lunchpail-controller-probe" ]
            ++ pkgs.lib.optionals (system == "x86_64-linux") [ "--features" "rocm-ocr" ];
          postBuild = ''
            python3 packaging/build-inference.py --offline --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget}
          '';
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            export QML2_IMPORT_PATH="${qtEnv}/lib/qt-6/qml"
            export QML_IMPORT_PATH="${qtEnv}/lib/qt-6/qml"
            export QT_PLUGIN_PATH="${qtEnv}/lib/qt-6/plugins"
            export XDG_CACHE_HOME="$TMPDIR/lunchpail-test-cache"
            # Display-session tests write private RetroArch appendconfigs via
            # ProjectDirs. A Nix build has no writable user home.
            export XDG_DATA_HOME="$TMPDIR/lunchpail-test-data"
            mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
            QT_QPA_PLATFORM=offscreen qmltestrunner \
              -input crates/lunchpail-app/tests/qml
            # Include Lunchpail's C++ text snapping, which ordinary QML tests
            # do not install. Repeated release changes must not drift labels.
            "$QT_LIBEXEC_PATH/moc" crates/lunchpail-app/tests/button_labels.cpp \
              -o "$TMPDIR/button_labels.moc"
            $CXX -std=c++17 -fPIC crates/lunchpail-app/tests/button_labels.cpp \
              -Icrates/lunchpail-app/include -I"$TMPDIR" \
              $(pkg-config --cflags --libs Qt6QuickTest Qt6Quick Qt6Qml Qt6Gui Qt6Core) \
              -o "$TMPDIR/button-label-tests"
            QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=1.3 "$TMPDIR/button-label-tests" \
              -input crates/lunchpail-app/tests/qml/tst_button_labels.qml
            $CXX -std=c++17 -fPIC crates/lunchpail-app/tests/ui_settings_migration.cpp \
              -Icrates/lunchpail-app/include $(pkg-config --cflags --libs Qt6Core) \
              -o "$TMPDIR/ui-settings-migration-tests"
            "$TMPDIR/ui-settings-migration-tests"
            cargo test --package lunchpail-app --lib --release \
              ${pkgs.lib.optionalString (system == "x86_64-linux") "--features rocm-ocr"} \
              --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget}
            runHook postCheck
          '';
          postInstall = ''
            install -m0755 target/inference/lunchpail-*-cpu target/inference/lunchpail-*-gpu "$out/bin/"
            mkdir -p "$out/share/lunchpail"
            cp -R packaging/inference-licenses "$out/share/lunchpail/"
            7z x -y "artifacts/lunchpail.db.7z" "-o$out/share/lunchpail" >/dev/null
            install -Dm644 assets/lunchpail.svg \
              "$out/share/icons/hicolor/scalable/apps/io.github.benwbooth.Lunchpail.svg"
            install -Dm644 packaging/io.github.benwbooth.Lunchpail.desktop \
              "$out/share/applications/io.github.benwbooth.Lunchpail.desktop"
            install -Dm644 packaging/io.github.benwbooth.Lunchpail.metainfo.xml \
              "$out/share/metainfo/io.github.benwbooth.Lunchpail.metainfo.xml"
          '';
          preFixup = ''
            qtWrapperArgs+=(--prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.xdelta ]}")
            qtWrapperArgs+=(--set LUNCHPAIL_DATABASE "$out/share/lunchpail/lunchpail.db")
            qtWrapperArgs+=(--set ORT_DYLIB_PATH "${onnxruntimeForHost}/lib/${if pkgs.stdenv.hostPlatform.isDarwin then "libonnxruntime.dylib" else "libonnxruntime.so"}")
          '' + pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            qtWrapperArgs+=(--prefix PATH : "${pkgs.lib.makeBinPath [ dwarfs ]}")
            # Qt discovers Flite voice libraries dynamically rather than via
            # the engine plugin's RPATH. Nix has no /usr/lib fallback.
            qtWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${pkgs.lib.getLib pkgs.flite}/lib")
          '';
          meta = with pkgs.lib; {
            description = "Native Rust and Qt game library frontend";
            license = licenses.mit;
            mainProgram = "lunchpail";
            platforms = platforms.linux ++ platforms.darwin;
          };
        };
        # Iteration builds: identical frontend without the release test
        # suite. `nix run .#lunchpail-fast` launches in a fraction of the
        # time; the default package keeps full gates for CI and commits.
        # The fast profile also drops release LTO/single-codegen (parallel
        # codegen, no thin-LTO link) via pure env overrides.
        frontendFast = frontend.overrideAttrs (previous: {
          pname = "lunchpail-fast";
          doCheck = false;
          CARGO_PROFILE_RELEASE_LTO = "false";
          CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
        });
      in
      {
        checks.controller-probe = controllerProbe;
        packages = {
          default = frontend;
          lunchpail = frontend;
          lunchpail-fast = frontendFast;
          lunchpail-db = databaseTool;
          lunchpail-controller-probe = controllerProbe;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          simcoupe-controller = pkgs.callPackage ./packaging/simcoupe-controller.nix { };
          retroarch-relative-routing = pkgs.callPackage ./packaging/retroarch-relative-routing.nix { };
          mame-game-mouse-only = pkgs.callPackage ./packaging/mame-game-mouse-only.nix { };
        } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          onnxruntime-rocm = onnxruntimeRocm;
        };

        apps.default = {
          type = "app";
          program = "${frontend}/bin/lunchpail";
        };

        apps.lunchpail-db = {
          type = "app";
          program = "${databaseTool}/bin/lunchpail-db";
        };

        apps.lunchpail-controller-probe = {
          type = "app";
          program = "${controllerProbe}/bin/lunchpail-controller-probe";
        };

        apps.lunchpail-fast = {
          type = "app";
          program = "${frontendFast}/bin/lunchpail";
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.rustPlatform.bindgenHook ];
          LUNCHPAIL_SDL3_LIBRARY = "${pkgs.lib.getLib pkgs.sdl3}/lib/${if pkgs.stdenv.hostPlatform.isDarwin then "libSDL3.dylib" else "libSDL3.so.0"}";
          packages = (with pkgs; [
            cargo
            cmake
            clippy
            ninja
            p7zip
            pkg-config
            rust-analyzer
            rustc
            rustfmt
            sqlite
            watchexec
            xdelta
          ]) ++ qtModules ++ [ onnxruntimeForHost ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            dwarfs
            pkgs.mold
            pkgs.systemd
            pkgs.alsa-lib
            pkgs.shaderc
            pkgs.spirv-headers
            pkgs.vulkan-headers
            pkgs.vulkan-loader
          ];

          SHERPA_ONNX_LIB_DIR = "${sherpaLibraries}/lib";
          QMAKE = "${qtEnv}/bin/qmake";
          ORT_LIB_PATH = "${onnxruntimeForHost}/lib";
          ORT_DYLIB_PATH = "${onnxruntimeForHost}/lib/${if pkgs.stdenv.hostPlatform.isDarwin then "libonnxruntime.dylib" else "libonnxruntime.so"}";
          ORT_PREFER_DYNAMIC_LINK = "1";
          LIBCHDMAN_PREBUILT_LOCAL_ARCHIVE = "${chdmanArchive}";
          QT_QPA_PLATFORM = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "wayland;xcb";
          # Local dev builds show the real build time; release builds set the
          # pinned flake time instead.
          LUNCHPAIL_BUILT_UNIX = "now";

          shellHook = ''
            export PATH="${qtEnv}/bin:${qtEnv}/libexec:$PATH"
            export QMAKE="${qtEnv}/bin/qmake"
            export QT_INCLUDE_PATH="${qtEnv}/include"
            export QT_LIBEXEC_PATH="${qtEnv}/libexec"
            # mold only exists in the dev shell (Linux); nix builds use the
            # default linker so sandboxed derivations stay reproducible.
            ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
              export RUSTFLAGS="''${RUSTFLAGS:-} -C link-arg=-fuse-ld=mold"
              export LD_LIBRARY_PATH="${pkgs.lib.getLib pkgs.flite}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            ''}
            # Incremental dev loop: rebuild the app on any code change and
            # restart it, instead of waiting on a release build or CI. The
            # first debug link takes a few minutes; later one-file Rust
            # rebuilds are around twenty seconds.
            lunchpail-dev() {
              watchexec --restart --shell=none \
                --watch crates \
                --watch vendor \
                --watch Cargo.toml \
                --watch Cargo.lock \
                --exts rs,qml,json,toml,lock \
                -- cargo run -p lunchpail-app --bin lunchpail
            }
            export -f lunchpail-dev 2>/dev/null || true
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
