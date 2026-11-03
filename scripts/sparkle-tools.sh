#!/usr/bin/env bash
# Print the directory holding Sparkle 2's command-line tools (generate_keys,
# sign_update, generate_appcast), downloading the pinned release into
# build/sparkle/ when needed. Sparkle is never vendored in git.
#
# Usage: scripts/sparkle-tools.sh            -> prints the bin directory
#        BIN="$(scripts/sparkle-tools.sh)" && "$BIN/sign_update" --account copera-currency <file>
#
# Lookup order: SPARKLE_BIN env, the SPM artifacts xcodebuild resolved for this
# project (once Sparkle is a package dependency), then the pinned tarball.
set -euo pipefail

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."
ROOT="$PWD"

has_tools() { [[ -x "$1/sign_update" && -x "$1/generate_keys" ]]; }

if [[ -n "${SPARKLE_BIN:-}" ]]; then
  has_tools "$SPARKLE_BIN" || die "SPARKLE_BIN=$SPARKLE_BIN has no sign_update/generate_keys"
  echo "$SPARKLE_BIN"
  exit 0
fi

for d in "$ROOT/build/release/DerivedData" "$ROOT/build/DerivedData"; do
  bin="$d/SourcePackages/artifacts/sparkle/Sparkle/bin"
  if has_tools "$bin"; then echo "$bin"; exit 0; fi
done

DEST="$ROOT/build/sparkle/$SPARKLE_VERSION"
if ! has_tools "$DEST/bin"; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download Sparkle"
  url="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/sparkle.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading Sparkle $SPARKLE_VERSION tools into build/sparkle/" >&2
  curl -fsSL "$url" -o "$tmp/sparkle.tar.xz" || die "could not download $url"
  sum="$(shasum -a 256 "$tmp/sparkle.tar.xz" | cut -d' ' -f1)"
  [[ "$sum" == "$SPARKLE_SHA256" ]] || die "Sparkle tarball sha256 mismatch (got $sum)"
  mkdir -p "$tmp/x"
  tar -xJf "$tmp/sparkle.tar.xz" -C "$tmp/x"
  has_tools "$tmp/x/bin" || die "Sparkle tarball has no bin/sign_update"
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  mv "$tmp/x" "$DEST"
fi
echo "$DEST/bin"
