#!/bin/zsh
# Builds Floatr (Release), installs it in /Applications, relaunches it and checks its resource use.
# Usage: tools/build.sh            build, install, check
#        tools/build.sh --zip      also write build/release/Floatr.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."

# Build outside the project folder: ~/Documents syncs with iCloud Drive, which tags bundle
# folders with attributes that break code signing.
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Floatr-cli"

python3 tools/gen_project.py >/dev/null
LOG="$DERIVED/build.log"
mkdir -p "$DERIVED"
if ! xcodebuild -project Floatr.xcodeproj -scheme Floatr -configuration Release -destination 'generic/platform=macOS' \
     -derivedDataPath "$DERIVED" -allowProvisioningUpdates build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" || tail -30 "$LOG"
  echo "✗ Build failed (full log: $LOG)"
  exit 1
fi
BUILT="$DERIVED/Build/Products/Release/Floatr.app"
xattr -cr "$BUILT"
codesign --verify --deep --strict "$BUILT"
echo "Built and verified $(defaults read "$BUILT/Contents/Info" CFBundleShortVersionString)"

# Replace the installed copy and keep only /Applications registered (so Safari loads that one).
pkill -x Floatr || true
# Safari keeps the old extension process alive; quit it so the next command loads the new one.
pkill -f "Floatr Extension.appex/Contents/MacOS/" || true
sleep 1
rm -rf /Applications/Floatr.app
ditto "$BUILT" /Applications/Floatr.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$BUILT" || true
open -g /Applications/Floatr.app
echo "Installed /Applications/Floatr.app"

if [[ "${1:-}" == "--zip" ]]; then
  mkdir -p build/release
  rm -f build/release/Floatr.zip
  ditto -c -k --keepParent "$BUILT" build/release/Floatr.zip
  echo "Wrote build/release/Floatr.zip"
fi

# Wait out launch work (including the daily update check, which uses the network) so the
# measurement shows the app at rest.
sleep 15
tools/check_resources.sh /Applications/Floatr.app
