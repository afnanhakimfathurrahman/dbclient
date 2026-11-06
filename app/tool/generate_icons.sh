#!/bin/bash
# Renders every platform's app icon from assets/icon/app_icon.svg (the same
# icon as the website). Needs librsvg2-bin, imagemagick and icoutils; from
# Windows, run it in a container from the app folder:
#   podman run --rm -v "$PWD:/app" -w /app ubuntu:24.04 bash -c \
#     "apt-get update -qq && apt-get install -y -qq librsvg2-bin imagemagick icoutils >/dev/null && bash tool/generate_icons.sh"
set -euo pipefail

src=assets/icon/app_icon.svg
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# In-app copy, used as the Linux window icon.
render "$src" 256 assets/icon/app_icon.png

# Windows: multi-size .ico (256 is stored as PNG).
for s in 16 20 24 32 40 48 64 128 256; do render "$src" $s "$tmp/w$s.png"; done
icotool -c -o windows/runner/resources/app_icon.ico \
  "$tmp"/w16.png "$tmp"/w20.png "$tmp"/w24.png "$tmp"/w32.png "$tmp"/w40.png \
  "$tmp"/w48.png "$tmp"/w64.png "$tmp"/w128.png -r "$tmp"/w256.png

# macOS: Apple's grid puts the shape at 824 of 1024 pixels, centred.
render "$src" 824 "$tmp/mac824.png"
convert -size 1024x1024 xc:none "$tmp/mac824.png" -gravity center -composite "$tmp/mac1024.png"
for s in 16 32 64 128 256 512 1024; do
  convert "$tmp/mac1024.png" -resize ${s}x${s} \
    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png
done

# Android launcher icons.
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render "$src" "${pair#*:}" "android/app/src/main/res/mipmap-${pair%%:*}/ic_launcher.png"
done

# iOS: square and opaque (the system rounds the corners; alpha is rejected).
sed 's/rx="112"/rx="0"/' "$src" > "$tmp/square.svg"
for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  name=$(basename "$f" .png)              # Icon-App-83.5x83.5@2x
  points=${name#Icon-App-}; points=${points%%x*}
  scale=${name##*@}; scale=${scale%x}
  px=$(awk "BEGIN { printf \"%d\", $points * $scale + 0.5 }")
  render "$tmp/square.svg" "$px" "$tmp/ios.png"
  convert "$tmp/ios.png" -background '#0f172a' -alpha remove -alpha off "$f"
done

echo "Icons generated."
