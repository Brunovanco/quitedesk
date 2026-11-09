#!/bin/bash
# Quitegood Support - local macOS Apple Silicon build (mirrors upstream CI job build-for-macOS/aarch64)
# Idempotent: re-run it after a failure, finished phases are skipped.
# Usage: bash build-arm.sh [phase]   phases: deps rust flutter vcpkg src bridge build dmg publish
set -euo pipefail
B="$HOME/quitegood-build"; mkdir -p "$B/bin" "$B/.done"
FLUTTER_VERSION=3.44.9
BRIDGE_FLUTTER_VERSION=3.44.8   # upstream bridge.yml (only the generator; harmless if same as build)
MAC_RUST_VERSION=1.81
BRIDGE_RUST_VERSION=1.75
FRB_VERSION=1.80.1
CARGO_EXPAND_VERSION=1.0.95
VCPKG_COMMIT_ID=9e593bb18ea69cc5095e012465dcd675a822ed0d
MIN_MACOS=12.3
REPO=https://github.com/Brunovanco/quitedesk.git
BRANCH=quitegood

export PATH="$B/bin:$B/flutter/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export VCPKG_ROOT="$B/vcpkg"
log(){ echo; echo "=== [$(date +%H:%M:%S)] $*"; }
done_(){ touch "$B/.done/$1"; }
is_done(){ [ -f "$B/.done/$1" ]; }
want(){ [ -z "${ONLY:-}" ] || [ "$ONLY" = "$1" ]; }
ONLY="${1:-}"

# ---------- 0. Xcode is a prerequisite (App Store, needs the user's Apple ID)
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "XCODE_MISSING: installez Xcode depuis l'App Store, ouvrez-le une fois (licence), puis relancez."
  exit 3
fi
[ "$(uname -m)" = arm64 ] || { echo "Ce script est prévu pour un Mac Apple Silicon"; exit 4; }
sudo -n true 2>/dev/null || true

# ---------- 1. Homebrew packages
if want deps && ! is_done deps; then
  log "Homebrew + outils"
  if ! command -v brew >/dev/null; then
    echo "BREW_MISSING"; exit 5
  fi
  brew install llvm create-dmg pkg-config gnu-sed cocoapods cmake ninja automake autoconf libtool
  # NASM 2.16 (upstream: NASM 3.x breaks some multimedia ports)
  if ! "$B/bin/nasm" -v 2>/dev/null | grep -q "2.16"; then
    cd "$B" && curl -fsSLO https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/macosx/nasm-2.16.03-macosx.zip
    unzip -oq nasm-2.16.03-macosx.zip && cp nasm-2.16.03/nasm "$B/bin/nasm"
  fi
  done_ deps
fi

# ---------- 2. Rust
if want rust && ! is_done rust; then
  log "Rust $MAC_RUST_VERSION + $BRIDGE_RUST_VERSION"
  command -v rustup >/dev/null || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
  rustup toolchain install $MAC_RUST_VERSION --profile minimal -c rustfmt -t aarch64-apple-darwin
  rustup toolchain install $BRIDGE_RUST_VERSION --profile minimal -c rustfmt
  done_ rust
fi

# ---------- 3. Flutter
if want flutter && ! is_done flutter; then
  log "Flutter $FLUTTER_VERSION"
  [ -d "$B/flutter" ] || git clone --depth 1 -b $FLUTTER_VERSION https://github.com/flutter/flutter.git "$B/flutter"
  flutter config --no-analytics >/dev/null
  flutter config --no-enable-swift-package-manager
  flutter --version
  # https://github.com/flutter/flutter/issues/133533 (same workaround as upstream CI)
  gsed -i -e 's/_setFramesEnabledState(false);/\/\/_setFramesEnabledState(false);/g' "$B/flutter/packages/flutter/lib/src/scheduler/binding.dart"
  done_ flutter
fi

# ---------- 4. Sources
if want src && ! is_done src; then
  log "Sources $REPO ($BRANCH)"
  rm -rf "$B/src"
  git clone --depth 1 -b $BRANCH --recurse-submodules --shallow-submodules $REPO "$B/src"
  cd "$B/src"
  PATH="$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" bash .github/patches/apply_flutter_3.44_source_patches.sh
  # minimum macOS 12.3 for arm64 (as upstream CI)
  gsed -i -e "s/MACOSX_DEPLOYMENT_TARGET\=[0-9]*.[0-9]*/MACOSX_DEPLOYMENT_TARGET=${MIN_MACOS}/" build.py
  gsed -i -e "s/platform :osx, '.*'/platform :osx, '${MIN_MACOS}'/" flutter/macos/Podfile
  gsed -i -e "s/osx_minimum_system_version = \"[0-9]*.[0-9]*\"/osx_minimum_system_version = \"${MIN_MACOS}\"/" Cargo.toml
  gsed -i -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = ${MIN_MACOS};/" flutter/macos/Runner.xcodeproj/project.pbxproj
  # Xcode 26+ refuses pod targets below macOS 12: force every pod to MIN_MACOS
  grep -q "QG_MIN_MACOS" flutter/macos/Podfile || gsed -i -e "s/    flutter_additional_macos_build_settings(target)/    flutter_additional_macos_build_settings(target)\n    target.build_configurations.each { |c| c.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '${MIN_MACOS}' } # QG_MIN_MACOS/" flutter/macos/Podfile
  grep -q '"key": "__QG_SERVER_KEY__"' quitegood/settings.json && { echo "server key missing"; exit 6; }
  done_ src
fi

# ---------- 5. vcpkg dependencies (ffmpeg, libvpx, aom, opus...) - the long one
if want vcpkg && ! is_done vcpkg; then
  log "vcpkg $VCPKG_COMMIT_ID (long : 30-60 min)"
  if [ ! -d "$VCPKG_ROOT/.git" ]; then git clone https://github.com/microsoft/vcpkg "$VCPKG_ROOT"; fi
  git -C "$VCPKG_ROOT" fetch -q origin $VCPKG_COMMIT_ID 2>/dev/null || true
  git -C "$VCPKG_ROOT" checkout -q $VCPKG_COMMIT_ID
  [ -x "$VCPKG_ROOT/vcpkg" ] || "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
  cd "$B/src"
  if ! "$VCPKG_ROOT/vcpkg" install --triplet arm64-osx --x-install-root="$VCPKG_ROOT/installed"; then
    find "$VCPKG_ROOT/buildtrees" -name "*.log" -newer "$B/.done/src" -exec tail -n 30 {} \; | tail -n 120
    exit 7
  fi
  done_ vcpkg
fi

# ---------- 6. flutter_rust_bridge generated code
if want bridge && ! is_done bridge; then
  log "flutter_rust_bridge $FRB_VERSION"
  cargo +$BRIDGE_RUST_VERSION install cargo-expand --version $CARGO_EXPAND_VERSION --locked
  cargo +$BRIDGE_RUST_VERSION install flutter_rust_bridge_codegen --version $FRB_VERSION --features uuid --locked
  cd "$B/src/flutter" && flutter pub get && cd ..
  export LIBCLANG_PATH="$(brew --prefix llvm)/lib"
  RUSTUP_TOOLCHAIN=$BRIDGE_RUST_VERSION flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs \
     --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h \
     --llvm-path "$(brew --prefix llvm)"
  cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h
  done_ bridge
fi

# ---------- 7. Build (cargo + flutter build macos)
if want build && ! is_done build; then
  log "Build RustDesk (arm64)"
  cd "$B/src"
  export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
  rustup override set $MAC_RUST_VERSION
  grep -q "QG_MIN_MACOS" flutter/macos/Podfile || gsed -i -e "s/    flutter_additional_macos_build_settings(target)/    flutter_additional_macos_build_settings(target)\n    target.build_configurations.each { |c| c.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '${MIN_MACOS}' } # QG_MIN_MACOS/" flutter/macos/Podfile
  grep -n -A2 "flutter_additional_macos_build_settings(target)" flutter/macos/Podfile
  # cargo part already built? skip it on re-runs
  SKIP=""; [ -f target/release/liblibrustdesk.dylib ] && [ -f "$B/.done/cargo" ] && SKIP="--skip-cargo"
  python3 ./build.py --flutter --hwcodec --unix-file-copy-paste --screencapturekit $SKIP || { [ -f target/release/liblibrustdesk.dylib ] && touch "$B/.done/cargo"; exit 8; }
  ls -la flutter/build/macos/Build/Products/Release/RustDesk.app/Contents/MacOS/
  done_ build
fi

# ---------- 8. dmg
if want dmg && ! is_done dmg; then
  log "dmg"
  cd "$B/src"
  APP=flutter/build/macos/Build/Products/Release/RustDesk.app
  file "$APP/Contents/MacOS/RustDesk"
  # ad-hoc signature so the bundle is consistent (no Developer ID available)
  codesign --force --deep -s - "$APP" || true
  rm -f "$B/QuitegoodSupport-macOS-AppleSilicon.dmg"
  create-dmg --skip-jenkins --volname "Quitegood Support" --app-drop-link 600 185 "$B/QuitegoodSupport-macOS-AppleSilicon.dmg" "$APP"
  shasum -a 256 "$B/QuitegoodSupport-macOS-AppleSilicon.dmg"
  done_ dmg
fi
log "OK"
