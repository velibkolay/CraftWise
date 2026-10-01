#!/usr/bin/env bash
# Builds the release zip: CraftWise/ only (no tests, tools or docs), version filled in.
# Usage: tools/package.sh <version>   -> dist/CraftWise-<version>.zip
set -euo pipefail
version="${1:?version, e.g. 0.2.0 or 0.2.0-beta.1}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$root/CraftWise" "$stage/CraftWise"
cp "$root/LICENSE" "$stage/CraftWise/LICENSE"
sed -i.bak "s/^## Version: .*/## Version: ${version}/" "$stage/CraftWise/CraftWise.toc"
rm -f "$stage/CraftWise/CraftWise.toc.bak"
find "$stage" -name '.DS_Store' -delete
mkdir -p "$out"
rm -f "$out/CraftWise-${version}.zip"
(cd "$stage" && zip -qr "$out/CraftWise-${version}.zip" CraftWise)
echo "$out/CraftWise-${version}.zip"
