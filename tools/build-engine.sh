#!/usr/bin/env bash
# Build the shared Kotlin Multiplatform engine from core/ for iOS and point the Xcode project at it.
#
#   tools/build-engine.sh sim      simulator framework only (the test build)
#   tools/build-engine.sh all      simulator and device (the TestFlight archive)
#
# Finds the Gradle module in core/ that declares iosSimulatorArm64, runs its link tasks, copies the frameworks to
# build/engine/<iphonesimulator|iphoneos>/ and writes engine.yml so XcodeGen links them. With no such module yet, it
# leaves engine.yml linking nothing and exits 0. The framework must be static (isStatic = true): the app does not
# embed it, it links it.
set -euo pipefail
which_targets="${1:-sim}"
if [ "$(uname)" != Darwin ]; then
  echo "The iOS engine builds only on a Mac (Kotlin/Native for iOS). Leaving engine.yml as it is."
  exit 0
fi
mod_file=$(grep -l "iosSimulatorArm64" core/*/build.gradle.kts core/*/*/build.gradle.kts 2>/dev/null | head -1 || true)
if [ -z "$mod_file" ]; then
  echo "No shared engine in core/ yet (no Gradle module with iosSimulatorArm64). Building with the stand-in engine."
  exit 0
fi
mod_dir=$(dirname "$mod_file")                 # core/<module> or core/<a>/<b>
rel=${mod_dir#core/}                            # <module> or <a>/<b>
gpath=":${rel//\//:}"
echo "Shared engine module: $mod_dir (Gradle $gpath)"

tasks=("$gpath:linkReleaseFrameworkIosSimulatorArm64")
[ "$which_targets" = all ] && tasks+=("$gpath:linkReleaseFrameworkIosArm64")
(cd core && ./gradlew --no-daemon -Pmm.coreOnly --stacktrace "${tasks[@]}")

copy() { # <kotlin target> <xcode platform>
  local src
  src=$(ls -d "$mod_dir"/build/bin/"$1"/releaseFramework/*.framework 2>/dev/null | head -1 || true)
  [ -n "$src" ] || { echo "No framework built for $1"; exit 1; }
  mkdir -p "build/engine/$2"
  rm -rf "build/engine/$2/$(basename "$src")"
  cp -R "$src" "build/engine/$2/"
  name=$(basename "$src" .framework)
  if ! file "build/engine/$2/$name.framework/$name" | grep -q "ar archive"; then
    echo "The $name framework is dynamic. Ask the Android chat for binaries.framework { isStatic = true }: the iOS app links, it does not embed."
    exit 1
  fi
  echo "$name"
}
name=$(copy iosSimulatorArm64 iphonesimulator | tail -1)
[ "$which_targets" = all ] && copy iosArm64 iphoneos >/dev/null

cat > engine.yml <<YML
# Written by tools/build-engine.sh: links the shared Kotlin engine ($name) built from $mod_dir.
targets:
  MessMachine:
    settings:
      base:
        FRAMEWORK_SEARCH_PATHS: ["\$(inherited)", "\$(PROJECT_DIR)/build/engine/\$(PLATFORM_NAME)"]
        OTHER_LDFLAGS: ["\$(inherited)", "-framework", "$name", "-lc++"]
  MessMachineTests:
    settings:
      base:
        FRAMEWORK_SEARCH_PATHS: ["\$(inherited)", "\$(PROJECT_DIR)/build/engine/\$(PLATFORM_NAME)"]
YML
# the Swift view of the framework, for whoever wires a new engine call (printed in the CI log, kept in build/)
hdr="build/engine/iphonesimulator/$name.framework/Headers/$name.h"
[ -f "$hdr" ] && cp "$hdr" "build/engine/$name.h"
echo "Linked the shared engine: $name"
