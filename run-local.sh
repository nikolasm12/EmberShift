#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}"
derived_data="${TMPDIR:-/tmp}/RedLightInstalledRelease"
install_directory="$HOME/Applications"

xcodebuild \
  -project "$project_root/RedLight.xcodeproj" \
  -scheme "RedLight" \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CONFIGURATION_BUILD_DIR="$install_directory" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

open "$install_directory/RedLight.app"
