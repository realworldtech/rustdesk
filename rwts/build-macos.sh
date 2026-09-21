#!/usr/bin/env bash
# Build, sign, notarize and upload the macOS QuickSupport DMGs on a Mac.
#
# There is no macOS runner on the internal GitHub, so a team member runs this
# on any Mac with Xcode for each release. It repeats the macOS job of the
# upstream workflow for the host architecture only.
#
# Usage:  rwts/build-macos.sh <version> [arch]     # e.g. 1.4.9-1 x86_64
#         arch is x86_64 or arm64; the default is the host. An arm64 Mac can
#         cross-build x86_64 (cargo --target plus the vcpkg x64-osx triplet).
# Needs:  Xcode, Homebrew, rustup, flutter 3.24.5 on PATH, rwts-sign
#         (RWTS_SIGN_TOKEN set or a chmod 600 .rwts-sign.credentials),
#         gh authenticated to github.realworld.net.au.
set -euo pipefail
VERSION="${1:?usage: rwts/build-macos.sh <version>}"
cd "$(dirname "$0")/.."
APP_NAME="RWTS QuickSupport"
ARCH="${2:-$(uname -m)}"
case "$ARCH" in x86_64|arm64) ;; *) echo "arch must be x86_64 or arm64" >&2; exit 1;; esac
TARGET=$([ "$ARCH" = arm64 ] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
TRIPLET=$([ "$ARCH" = arm64 ] && echo arm64-osx || echo x64-osx)
export MAC_ARCH="$ARCH"
EXTRA=$([ "$ARCH" = arm64 ] && echo "--screencapturekit" || echo "")

command -v rwts-sign >/dev/null || pipx install rwts-sign --pip-args "--index-url https://devpi.realworld.net.au/realworld/dev/+simple/"
brew list create-dmg pkgconf cocoapods >/dev/null 2>&1 || brew install create-dmg pkgconf cocoapods
if ! nasm --version 2>/dev/null | grep -q 'version 2\.'; then
  echo "NASM 2.16.x is required (NASM 3.x breaks aom). Install from https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/macosx/" >&2
  exit 1
fi
rustup toolchain install 1.81 --profile minimal >/dev/null
rustup target add --toolchain 1.81 "$TARGET" >/dev/null
rustup component add rustfmt --toolchain 1.81 >/dev/null
export RUSTUP_TOOLCHAIN=1.81
flutter --version | head -1 | grep -q "3.24.5" || { echo "flutter 3.24.5 required" >&2; exit 1; }

# bindgen 0.59 in libs/scrap cannot parse headers through a very new Homebrew
# libclang (silently emits empty structs). Use Xcode's libclang instead.
XCODE_LIBCLANG="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"
[ -f "$XCODE_LIBCLANG/libclang.dylib" ] && export LIBCLANG_PATH="$XCODE_LIBCLANG"

# Bridge files (normally produced by the generate-bridge job).
if [ ! -f src/bridge_generated.rs ] || [ ! -f flutter/lib/generated_bridge.dart ]; then
  cargo install cargo-expand --version 1.0.95 --locked
  cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
  (cd flutter && flutter pub get)
  ~/.cargo/bin/flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h
fi

# vcpkg native libraries.
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
if [ ! -x "$VCPKG_ROOT/vcpkg" ]; then
  git clone -q https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
  (cd "$VCPKG_ROOT" && git checkout -q 120deac3062162151622ca4860575a33844ba10b && ./bootstrap-vcpkg.sh -disableMetrics)
fi
# ffmpeg is a "host" dependency in vcpkg.json; pin the host triplet too or a cross build gets the wrong one.
"$VCPKG_ROOT/vcpkg" install --triplet "$TRIPLET" --host-triplet "$TRIPLET" --x-install-root="$VCPKG_ROOT/installed"

# Xcode 27 refuses the upstream 10.14 deployment target, so both architectures build for 12.3.
if true; then
  MIN=12.3
  sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET\=[0-9]*.[0-9]*/MACOSX_DEPLOYMENT_TARGET=${MIN}/" build.py
  sed -i '' -e "s/platform :osx, '.*'/platform :osx, '${MIN}'/" flutter/macos/Podfile
  sed -i '' -e "s/osx_minimum_system_version = \"[0-9]*.[0-9]*\"/osx_minimum_system_version = \"${MIN}\"/" Cargo.toml
  sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = ${MIN};/" flutter/macos/Runner.xcodeproj/project.pbxproj
fi
# Xcode adds com.apple.security.get-task-allow to ad-hoc ("-") signatures.
# rcodesign keeps the entitlements it finds, and Apple's notary rejects that one.
export FLUTTER_XCODE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
# Products left by a build for the other architecture break the Flutter link step.
rm -rf flutter/build/macos
./build.py --flutter --hwcodec --unix-file-copy-paste $EXTRA
git checkout -q build.py flutter/macos/Podfile Cargo.toml flutter/macos/Runner.xcodeproj/project.pbxproj || true

APP="flutter/build/macos/Build/Products/Release/${APP_NAME}.app"
# Uploads of ~30 MB sometimes hit a write timeout; one retry covers that.
sign() { rwts-sign "$@" || { echo "rwts-sign failed, retrying once" >&2; sleep 10; rwts-sign "$@"; }; }
mkdir -p SignOutput
for flavour in quicksupport technician; do
  W="/tmp/qs-$flavour"; rm -rf "$W"; mkdir -p "$W"
  cp -R "$APP" "$W/${APP_NAME}.app"
  cp "rwts/${flavour}.custom.txt" "$W/${APP_NAME}.app/Contents/Resources/custom.txt"
  ditto -c -k --keepParent "$W/${APP_NAME}.app" "$W/app.zip"
  sign macos-app "$W/app.zip" --notarize
  rm -rf "$W/${APP_NAME}.app"; ditto -x -k "$W/app.zip" "$W/"
  if [ "$flavour" = technician ]; then OUT="SignOutput/RWTS-QuickSupport-Tech-${VERSION}-${ARCH}.dmg"; else OUT="SignOutput/RWTS-QuickSupport-${VERSION}-${ARCH}.dmg"; fi
  rm -f "$OUT"
  create-dmg --icon "${APP_NAME}.app" 200 190 --hide-extension "${APP_NAME}.app" --window-size 800 400 --app-drop-link 600 185 "$OUT" "$W/${APP_NAME}.app"
  sign macos-dmg "$OUT" --notarize
  xcrun stapler validate "$OUT"
done
ls -la SignOutput/*.dmg

if GH_HOST=github.realworld.net.au gh release view "rwts/${VERSION}" -R realworldtech/rustdesk >/dev/null 2>&1; then
  GH_HOST=github.realworld.net.au gh release upload "rwts/${VERSION}" SignOutput/*.dmg --clobber -R realworldtech/rustdesk
  echo "Uploaded to release rwts/${VERSION} on github.realworld.net.au"
else
  echo "Release rwts/${VERSION} does not exist yet. Upload later with:"
  echo "  GH_HOST=github.realworld.net.au gh release upload rwts/${VERSION} SignOutput/*.dmg -R realworldtech/rustdesk"
fi
