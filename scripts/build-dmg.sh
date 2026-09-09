#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-1.0.0}"
build_root="$repo_root/build"
derived_data="$build_root/deriveddata"
staging_root="$build_root/dmgroot"
release_dir="$repo_root/website/downloads"
dmg_path="$release_dir/brewstore-${version}.dmg"

cd "$repo_root"

/opt/homebrew/bin/xcodegen generate
xcodebuild \
  -project BrewStore.xcodeproj \
  -scheme BrewStore \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  build

app_path="$derived_data/Build/Products/Release/BrewStore.app"
if [[ ! -d "$app_path" ]]; then
  print -u2 "BrewStore.app was not produced at $app_path"
  exit 1
fi

rm -rf "$staging_root"
mkdir -p "$staging_root"
ditto "$app_path" "$staging_root/BrewStore.app"
ln -s /Applications "$staging_root/Applications"

mkdir -p "$release_dir"
rm -f "$dmg_path"
sync

temp_dmg="$build_root/brewstore-temp.dmg"
rm -f "$temp_dmg"

hdiutil create \
  -volname "BrewStore" \
  -srcfolder "$staging_root" \
  -ov \
  -format UDZO \
  "$temp_dmg"

mv -f "$temp_dmg" "$dmg_path"
(cd "$release_dir" && shasum -a 256 "brewstore-${version}.dmg") | tee "$release_dir/brewstore-${version}.sha256"
print "Created $dmg_path"
