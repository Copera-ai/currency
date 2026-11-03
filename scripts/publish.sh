#!/usr/bin/env bash
# Publish a Copera Currency release to GitHub Releases end to end: preflight,
# build + notarize (scripts/release.sh), extend the Sparkle appcast, tag, push
# the tag, create the release with DMG + zip + checksums + appcast, verify.
#
# Usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]
# Env:   NOTARY_PROFILE  notarytool keychain profile (default: apple-notary)
#        GH_REPO         GitHub repo (default: Copera-ai/currency)
#        MIN_SYSTEM_VERSION  sparkle:minimumSystemVersion (default: 26.0)
#
# Tags are v<x.y.z>; the build number is `git rev-list --count HEAD` (always
# grows on main). Release notes come from the "## <x.y.z>" section of CHANGELOG.md.
#
# Sparkle 2: the app reads
#   https://github.com/<repo>/releases/latest/download/appcast.xml
# so every release carries the FULL appcast (all versions, newest first) as an
# asset; each item points at that version's DMG and is signed with the EdDSA key
# stored in the login keychain under account "copera-currency".
set -euo pipefail

TAG_PREFIX="v"
GH_REPO="${GH_REPO:-Copera-ai/currency}"
NOTARY_PROFILE="${NOTARY_PROFILE:-apple-notary}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-26.0}"
SPARKLE_ACCOUNT="copera-currency"
APP_TITLE="Copera Currency"

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# version_gt <a> <b>: true when a > b (numeric x.y.z compare).
version_gt() {
  local IFS=. a b i
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do
    ((10#${a[i]} > 10#${b[i]})) && return 0
    ((10#${a[i]} < 10#${b[i]})) && return 1
  done
  return 1
}

# Latest vX.Y.Z tag reachable from HEAD, without the prefix (empty when none).
last_tag_version() {
  git tag --list "${TAG_PREFIX}*" --merged HEAD | sed "s/^$TAG_PREFIX//" \
    | { grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# changelog_section <file> <version>: body of "## <version>" (heading may carry
# a suffix such as " - 2026-11-03"), up to the next "## " heading, trimmed.
changelog_section() {
  awk -v v="$2" '
    /^## / {
      if (found) exit
      h = substr($0, 4); sub(/^\[/, "", h)
      if (h == v || index(h, v " ") == 1 || index(h, v "]") == 1) { found = 1; next }
    }
    found { print }
  ' "$1" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

# Minimal Markdown -> HTML for the Sparkle release notes (headings, bullets,
# paragraphs, `code`, **bold**). Input is escaped first, so "]]>" can't end the CDATA.
md_to_html() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | awk '
    function inline(s) {
      while (match(s, /`[^`]+`/)) s = substr(s, 1, RSTART-1) "<code>" substr(s, RSTART+1, RLENGTH-2) "</code>" substr(s, RSTART+RLENGTH)
      while (match(s, /\*\*[^*]+\*\*/)) s = substr(s, 1, RSTART-1) "<b>" substr(s, RSTART+2, RLENGTH-4) "</b>" substr(s, RSTART+RLENGTH)
      return s
    }
    function close_list() { if (inlist) { print "</ul>"; inlist = 0 } }
    /^[[:space:]]*$/ { close_list(); next }
    /^#+ / { close_list(); sub(/^#+ /, ""); print "<h3>" inline($0) "</h3>"; next }
    /^[[:space:]]*[-*] / { if (!inlist) { print "<ul>"; inlist = 1 } sub(/^[[:space:]]*[-*] /, ""); print "<li>" inline($0) "</li>"; next }
    { close_list(); print "<p>" inline($0) "</p>" }
    END { close_list() }
  '
}

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

empty_appcast() {
  cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_TITLE</title>
    <link>https://github.com/$GH_REPO/releases/latest/download/appcast.xml</link>
    <description>Updates for $APP_TITLE</description>
    <language>en</language>
  </channel>
</rss>
XML
}

# appcast_item <version> <build> <dmg url> <length> <ed signature> <notes html file>
appcast_item() {
  local pub
  pub="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  cat <<XML
    <item>
      <title>$APP_TITLE $1</title>
      <link>https://github.com/$GH_REPO/releases/tag/$TAG_PREFIX$1</link>
      <pubDate>$pub</pubDate>
      <sparkle:version>$2</sparkle:version>
      <sparkle:shortVersionString>$1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <description><![CDATA[
$(cat "$6")
      ]]></description>
      <enclosure url="$(printf '%s' "$3" | xml_escape)" length="$4" type="application/octet-stream" sparkle:edSignature="$5"/>
    </item>
XML
}

# insert_item <appcast in> <item file> <appcast out>: new item goes first (before
# the first existing <item>, or before </channel> in an empty feed).
insert_item() {
  awk -v itemfile="$2" '
    function emit(   l) { while ((getline l < itemfile) > 0) print l; close(itemfile); done = 1 }
    !done && /<item>/ { emit() }
    !done && /<\/channel>/ { emit() }
    { print }
  ' "$1" >"$3"
  grep -q "<sparkle:shortVersionString>" "$3" || return 1
}

# fetch_appcast <out>: appcast.xml of the latest release; an empty feed when the
# repo has no release yet or the latest release carries no appcast.
fetch_appcast() {
  local tmp latest
  tmp="$(mktemp -d)"
  latest="$(gh release view --repo "$GH_REPO" --json tagName -q .tagName 2>/dev/null || true)"
  if [[ -n "$latest" ]] && gh release download "$latest" --repo "$GH_REPO" --pattern appcast.xml --dir "$tmp" >/dev/null 2>&1; then
    mv "$tmp/appcast.xml" "$1"
    echo "appcast: extending the feed from release $latest"
  else
    empty_appcast >"$1"
    echo "appcast: no appcast.xml on a latest release; starting a fresh feed"
  fi
  rm -rf "$tmp"
}

main() {
  cd "$(dirname "$0")/.."
  local ROOT="$PWD" DIST WORK
  DIST="$ROOT/build/release/dist"
  WORK="$ROOT/build/release/publish"
  local DRY="${DRY_RUN:-0}"
  # In a dry run, problems that would block a real publish are only reported.
  blocker() { if [[ "$DRY" == 1 ]]; then warn "$* (ignored in DRY_RUN)"; else die "$*"; fi; }

  local version="${VERSION:-}"
  [[ -n "$version" ]] || die "usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be x.y.z (got '$version')"
  local tag="$TAG_PREFIX$version"

  step "Preflight"
  local cmd
  for cmd in git gh xcrun xcodegen xmllint shasum awk; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required"
  done
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"

  local branch dirty
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == main ]] || blocker "publish runs on main only (current branch: $branch)"
  dirty="$(git status --porcelain --untracked-files=normal)"
  [[ -z "$dirty" ]] || blocker "working tree is dirty; commit or stash first:
$dirty"
  git fetch --quiet origin main --tags || die "git fetch origin failed"
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || blocker "HEAD is not origin/main (pull or push first so the tag points at a published commit)"

  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && blocker "tag $tag already exists locally"
  [[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] || blocker "tag $tag already exists on origin"
  gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1 && blocker "release $tag already exists on $GH_REPO"

  local prev_version
  prev_version="$(last_tag_version)"
  if [[ -n "$prev_version" ]]; then
    version_gt "$version" "$prev_version" || blocker "VERSION $version is not newer than $prev_version"
  fi

  mkdir -p "$WORK"
  local notes_md="$WORK/notes-$version.md" notes_html="$WORK/notes-$version.html"
  if [[ -f CHANGELOG.md ]]; then
    changelog_section CHANGELOG.md "$version" >"$notes_md"
  else
    : >"$notes_md"
  fi
  if [[ ! -s "$notes_md" ]]; then
    blocker "CHANGELOG.md has no (or an empty) '## $version' section; add the release notes first"
    printf -- '- (DRY_RUN placeholder: no CHANGELOG.md section for %s)\n' "$version" >"$notes_md"
  fi
  md_to_html <"$notes_md" >"$notes_html"

  local sparkle_bin=""
  sparkle_bin="$(scripts/sparkle-tools.sh)" || die "could not locate or download the Sparkle tools"
  "$sparkle_bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null | grep -qE '^[A-Za-z0-9+/]{43}=$' \
    || blocker "no Sparkle EdDSA key for account '$SPARKLE_ACCOUNT' in the login keychain
  (import it with: $sparkle_bin/generate_keys --account $SPARKLE_ACCOUNT -f <private-key-file>)"
  if [[ "$DRY" != 1 ]]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
      || die "notary profile '$NOTARY_PROFILE' not usable (scripts/release.sh prints how to create it)"
    # Sign a scratch file now so the one-time keychain prompt ("sign_update wants
    # to use ... copera-currency": click Always Allow) appears before the build.
    echo "sign_update: checking keychain access (allow it if macOS asks)"
    printf 'probe' >"$WORK/sign-probe"
    "$sparkle_bin/sign_update" --account "$SPARKLE_ACCOUNT" "$WORK/sign-probe" >/dev/null \
      || die "sign_update could not use the '$SPARKLE_ACCOUNT' key from the login keychain"
  fi

  local build dmg zip sums appcast dmg_url
  build="$(git rev-list --count HEAD)"
  dmg="$DIST/Copera-Currency-$version.dmg"
  zip="$DIST/Copera-Currency-$version.zip"
  sums="$DIST/checksums.txt"
  appcast="$DIST/appcast.xml"
  dmg_url="https://github.com/$GH_REPO/releases/download/$tag/Copera-Currency-$version.dmg"
  echo "repo:     $GH_REPO"
  echo "previous: ${prev_version:-none (first release)}"
  echo "next:     $version (build $build, tag $tag)"

  if [[ "$DRY" == 1 ]]; then
    # Exercise the appcast generation with placeholder enclosure values.
    local dry_cast="$WORK/appcast.dry-run.xml" item="$WORK/item.xml"
    fetch_appcast "$WORK/appcast.base.xml"
    grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$WORK/appcast.base.xml" \
      && warn "$version is already in the live appcast (ignored in DRY_RUN)"
    appcast_item "$version" "$build" "$dmg_url" 0 DRY_RUN_SIGNATURE "$notes_html" >"$item"
    insert_item "$WORK/appcast.base.xml" "$item" "$dry_cast" || die "could not insert the appcast item"
    xmllint --noout "$dry_cast" || die "generated appcast is not well-formed XML ($dry_cast)"
    echo "appcast (dry run, placeholder length/signature) is well-formed: $dry_cast"

    step "Plan (DRY_RUN=1: nothing was built, tagged, pushed or released)"
    cat <<PLAN
1. scripts/release.sh $version --build $build   (archive, Developer ID, notarize, staple)
   -> $dmg
   -> $zip
   -> $sums
2. sign_update --account $SPARKLE_ACCOUNT on the DMG; prepend a $version item to the
   latest release's appcast.xml -> $appcast (xmllint-checked)
   enclosure: $dmg_url
3. git tag -a $tag -m "$APP_TITLE $version (build $build)"
4. git push origin $tag
5. gh release create $tag <dmg> <zip> checksums.txt appcast.xml --repo $GH_REPO \\
     --title "$APP_TITLE $version" --notes-file $notes_md --verify-tag --latest
6. gh release view $tag: assets present; appcast at
   https://github.com/$GH_REPO/releases/latest/download/appcast.xml lists $version (public repo only)

release notes ($notes_md):
$(sed 's/^/  | /' "$notes_md")
PLAN
    return 0
  fi

  if [[ "${YES:-0}" != 1 ]]; then
    local answer
    printf '\npublish %s %s (build %s) to %s? [y/N] ' "$APP_TITLE" "$version" "$build" "$GH_REPO"
    read -r answer </dev/tty || answer=""
    [[ "$answer" == [yY]* ]] || die "aborted"
  fi

  step "Building $version ($build)"
  NOTARY_PROFILE="$NOTARY_PROFILE" scripts/release.sh "$version" --build "$build"
  local f
  for f in "$dmg" "$zip" "$sums"; do
    [[ -f "$f" ]] || die "release did not produce $f"
  done

  step "Sparkle appcast"
  local sig item="$WORK/item.xml" ed len
  sig="$("$sparkle_bin/sign_update" --account "$SPARKLE_ACCOUNT" "$dmg")" || die "sign_update failed"
  ed="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$sig")"
  len="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$sig")"
  [[ -n "$ed" && "$len" == "$(stat -f %z "$dmg")" ]] || die "unexpected sign_update output"
  fetch_appcast "$WORK/appcast.base.xml"
  grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$WORK/appcast.base.xml" \
    && die "$version is already in the latest appcast"
  appcast_item "$version" "$build" "$dmg_url" "$len" "$ed" "$notes_html" >"$item"
  insert_item "$WORK/appcast.base.xml" "$item" "$appcast" || die "could not insert the appcast item"
  xmllint --noout "$appcast" || die "generated appcast is not well-formed XML ($appcast)"
  echo "appcast: $(grep -c '<item>' "$appcast") item(s), newest $version ($build)"

  step "Tagging $tag"
  git tag -a "$tag" -m "$APP_TITLE $version (build $build)"
  git push origin "refs/tags/$tag" || die "tag push failed; retry: git push origin $tag"

  step "Creating GitHub release $tag"
  gh release create "$tag" "$dmg" "$zip" "$sums" "$appcast" --repo "$GH_REPO" \
    --title "$APP_TITLE $version" --notes-file "$notes_md" --verify-tag --latest \
    || die "gh release create failed; the tag $tag is pushed. Fix and re-run the gh release create by hand"

  step "Verifying"
  local assets name
  assets="$(gh release view "$tag" --repo "$GH_REPO" --json assets -q '.assets[].name')"
  for name in "$(basename "$dmg")" "$(basename "$zip")" checksums.txt appcast.xml; do
    grep -qxF "$name" <<<"$assets" || die "release $tag is missing asset $name"
  done
  gh release view "$tag" --repo "$GH_REPO" --json tagName,name,isDraft,isPrerelease,url \
    -q '"\(.name) (\(.tagName)) draft=\(.isDraft) prerelease=\(.isPrerelease)\n\(.url)"'
  local feed="https://github.com/$GH_REPO/releases/latest/download/appcast.xml"
  if [[ "$(gh repo view "$GH_REPO" --json visibility -q .visibility 2>/dev/null)" == PUBLIC ]]; then
    curl -fsSL "$feed" | grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" \
      || die "$feed does not list $version"
    echo "feed OK: $feed lists $version"
  else
    warn "$GH_REPO is private: $feed is not publicly reachable, so Sparkle clients cannot update yet"
  fi

  step "Published $APP_TITLE $version (build $build)"
  echo "tag:      $tag"
  echo "feed:     $feed"
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
