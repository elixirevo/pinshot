#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
destination="$PWD/.build/sparkle"
if [[ -f "$destination/.version" && "$(cat "$destination/.version")" == "$version" &&
      -f "$destination/Sparkle.framework/Sparkle" && -x "$destination/bin/sign_update" ]]; then
    exit 0
fi

mkdir -p .build
temporary="$(mktemp -d "$PWD/.build/sparkle-setup.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
curl --fail --location --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
    -o "$temporary/Sparkle.tar.xz"
actual="$(shasum -a 256 "$temporary/Sparkle.tar.xz" | awk '{print $1}')"
if [[ "$actual" != "$checksum" ]]; then
    echo "Sparkle download checksum mismatch" >&2
    exit 1
fi
mkdir "$temporary/extracted"
tar -xf "$temporary/Sparkle.tar.xz" -C "$temporary/extracted"
test -f "$temporary/extracted/Sparkle.framework/Sparkle"
test -x "$temporary/extracted/bin/sign_update"
printf '%s\n' "$version" > "$temporary/extracted/.version"
rm -rf "$destination"
mv "$temporary/extracted" "$destination"
