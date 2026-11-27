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
# the shared screens and app logic (CMP step 7: core/ui, framework MessMachine, engine exported) win over the engine alone
mod_file=$(grep -l 'baseName = "MessMachine"' core/*/build.gradle.kts 2>/dev/null | head -1 || true)
gradle_flag="-Pmm.ios"
if [ -z "$mod_file" ]; then
  mod_file=$(grep -l "iosSimulatorArm64" core/*/build.gradle.kts core/*/*/build.gradle.kts 2>/dev/null | head -1 || true)
  gradle_flag="-Pmm.coreOnly"
fi
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
(cd core && ./gradlew --no-daemon "$gradle_flag" --stacktrace "${tasks[@]}")

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

# a shared framework with IosApp (core PR #26) takes over the app's lifecycle and incoming files from the Swift stopgaps
conds='"$(inherited)"'
if grep -q 'swift_name("IosApp")' "build/engine/iphonesimulator/$name.framework/Headers/$name.h" 2>/dev/null; then
  conds="$conds, \"MM_IOS_APP\""
  echo "The framework has IosApp: building with MM_IOS_APP"
fi

cat > engine.yml <<YML
# Written by tools/build-engine.sh: links the shared Kotlin engine ($name) built from $mod_dir.
targets:
  MessMachine:
    settings:
      base:
        FRAMEWORK_SEARCH_PATHS: ["\$(inherited)", "\$(PROJECT_DIR)/build/engine/\$(PLATFORM_NAME)"]
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: [$conds]
        OTHER_LDFLAGS: ["\$(inherited)", "-framework", "$name", "-lc++", "-lsqlite3", "-framework", "Metal", "-framework", "MetalKit", "-framework", "CoreText", "-framework", "CoreGraphics", "-framework", "QuartzCore", "-framework", "UIKit"]
  MessMachineTests:
    settings:
      base:
        FRAMEWORK_SEARCH_PATHS: ["\$(inherited)", "\$(PROJECT_DIR)/build/engine/\$(PLATFORM_NAME)"]
YML
# the Swift view of the framework, for whoever wires a new engine call (printed in the CI log, kept in build/)
hdr="build/engine/iphonesimulator/$name.framework/Headers/$name.h"
[ -f "$hdr" ] && cp "$hdr" "build/engine/$name.h"
# Compose resources (icons and fonts the shared screens draw): the app bundle's compose-resources folder, laid out the
# way Compose's iOS reader looks for them (composeResources/<package of Res>/<drawable|font>/...)
rm -rf build/compose-resources
if [ -d "$mod_dir/src/commonMain/composeResources" ]; then
  pkg=$(sed -n 's/.*packageOfResClass *= *"\([^"]*\)".*/\1/p' "$mod_file" | head -1)
  [ -n "$pkg" ] || pkg="$(basename "$mod_dir").generated.resources"
  mkdir -p "build/compose-resources/composeResources/$pkg"
  cp -R "$mod_dir/src/commonMain/composeResources/." "build/compose-resources/composeResources/$pkg/"
  echo "Compose resources: $(find build/compose-resources -type f | wc -l | tr -d ' ') files under composeResources/$pkg"
fi
echo "Linked the shared engine: $name"
