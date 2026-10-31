#!/usr/bin/env bash
# build-dmg.sh — build EarBud for release and package it as a DMG.
#
# Full release (task 10.1): Release build, Developer ID signature with the
# hardened runtime, DMG, notarization, stapling, and Gatekeeper checks.
#
#   scripts/release/build-dmg.sh
#
# Packaging test without a Developer ID (ad-hoc signature, no notarization):
#
#   scripts/release/build-dmg.sh --unsigned
#
# Environment:
#   EARBUD_SIGN_KEYCHAIN   dedicated keychain that holds the Developer ID
#                          identity. Never the login keychain: codesign against
#                          it blocks on a SecurityAgent dialog from a script.
#   EARBUD_SIGN_KC_PASS    password for that keychain. If unset, the keychain
#                          must already be unlocked.
#   EARBUD_SIGN_IDENTITY   identity SHA-1 or name (default: the Developer ID
#                          Application identity for team T348Z33H7K).
#   EARBUD_NOTARY_KEY      App Store Connect API key (.p8) for notarytool.
#   EARBUD_NOTARY_KEY_ID   its key ID.
#   EARBUD_NOTARY_ISSUER   its issuer ID.
#
# Output: build/release/EarBud-<version>.dmg

set -euo pipefail

UNSIGNED=0
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/release"
DERIVED="$OUT/DerivedData"
APP_NAME="EarBud"
ENTITLEMENTS="$ROOT/EarBud/Resources/EarBud.entitlements"

KEYCHAIN="${EARBUD_SIGN_KEYCHAIN:-$HOME/.openclaw/agents/scout/workspace/certs/parliament-signing.keychain-db}"
IDENTITY="${EARBUD_SIGN_IDENTITY:-69900FB15E716B9BF52BF035A7736B448399326E}"
NOTARY_KEY="${EARBUD_NOTARY_KEY:-$HOME/.appstoreconnect/keys/AuthKey_ARZQ5Q5V9M.p8}"
NOTARY_KEY_ID="${EARBUD_NOTARY_KEY_ID:-ARZQ5Q5V9M}"
NOTARY_ISSUER="${EARBUD_NOTARY_ISSUER:-6fb963ce-d88e-465c-b545-5b47bb4dd2d8}"
SIGN_TIMEOUT=120

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'build-dmg: %s\n' "$*" >&2; exit 1; }

command -v timeout >/dev/null || die "need 'timeout' on PATH (brew install coreutils)"

# Refuse to release uncommitted work: the DMG must match a commit.
if [[ $UNSIGNED -eq 0 && -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  die "working tree has uncommitted changes; commit or stash them first"
fi

if [[ $UNSIGNED -eq 0 ]]; then
  [[ -f "$KEYCHAIN" ]] || die "signing keychain not found: $KEYCHAIN"
  [[ -f "$NOTARY_KEY" ]] || die "notary key not found: $NOTARY_KEY"
fi

# --- Keychain: put the dedicated keychain first in the search list, and put
# the original list back on exit, whatever happens.
ORIGINAL_KEYCHAINS=()
restore_keychains() {
  if [[ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" 2>/dev/null \
      || echo "build-dmg: warning: could not restore the keychain search list" >&2
  fi
}
trap restore_keychains EXIT

if [[ $UNSIGNED -eq 0 ]]; then
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [[ -n "$line" ]] && ORIGINAL_KEYCHAINS+=("$line")
  done < <(security list-keychains -d user)
  [[ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]] || die "could not read the keychain search list"

  if [[ -n "${EARBUD_SIGN_KC_PASS:-}" ]]; then
    security unlock-keychain -p "$EARBUD_SIGN_KC_PASS" "$KEYCHAIN" || die "could not unlock $KEYCHAIN"
  fi
  security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
  IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN")"
  [[ "$IDENTITIES" == *"$IDENTITY"* ]] || die "identity $IDENTITY not found in $KEYCHAIN"
fi

sign() {
  # sign <codesign args...>; a timeout means a SecurityAgent dialog is up
  # (usually: the keychain is locked). Do not type a password into it.
  local status=0
  timeout "$SIGN_TIMEOUT" codesign --keychain "$KEYCHAIN" -s "$IDENTITY" "$@" || status=$?
  [[ $status -eq 124 ]] && die "codesign timed out; the signing keychain is probably locked"
  [[ $status -eq 0 ]] || die "codesign exited $status"
}

# --- Build
step "Release build"
rm -rf "$OUT"
mkdir -p "$OUT"
/usr/bin/xcodebuild build \
  -project "$ROOT/EarBud.xcodeproj" -scheme EarBud -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" > "$OUT/xcodebuild.log" 2>&1 \
  || { tail -30 "$OUT/xcodebuild.log" >&2; die "xcodebuild failed (log: $OUT/xcodebuild.log)"; }

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || die "build product missing: $BUILT_APP"

STAGE="$OUT/stage"
mkdir -p "$STAGE"
ditto "$BUILT_APP" "$STAGE/$APP_NAME.app"
APP="$STAGE/$APP_NAME.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
echo "EarBud $VERSION ($BUILD), commit $(git -C "$ROOT" rev-parse --short HEAD)"

# --- Sign the app. Nested code first (none today, but frameworks or helper
# tools added later must be signed before the bundle that contains them).
step "Sign app"
if [[ $UNSIGNED -eq 1 ]]; then
  codesign --force --deep -s - --options runtime --entitlements "$ENTITLEMENTS" "$APP"
else
  while IFS= read -r -d '' nested; do
    sign --force --options runtime --timestamp "$nested"
  done < <(find "$APP/Contents" \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.appex' \) -print0 2>/dev/null)
  sign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --strict --deep --verbose=2 "$APP"
SIGNATURE_INFO="$(codesign -d --verbose=2 "$APP" 2>&1)"
[[ "$SIGNATURE_INFO" == *"flags="*"runtime"* ]] || die "hardened runtime flag missing"

# --- DMG: the app plus an Applications shortcut to drag it onto.
step "DMG"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [[ $UNSIGNED -eq 1 ]]; then
  echo "Unsigned DMG: $DMG"
  exit 0
fi
sign --force --timestamp "$DMG"

# --- Notarize and staple
step "Notarize (usually a few minutes)"
SUBMIT_JSON="$OUT/notary-submit.json"
xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER" --wait --output-format json > "$SUBMIT_JSON" \
  || { cat "$SUBMIT_JSON" >&2; die "notarytool submit failed"; }
SUBMISSION_ID="$(/usr/bin/plutil -extract id raw "$SUBMIT_JSON")"
STATUS="$(/usr/bin/plutil -extract status raw "$SUBMIT_JSON")"
xcrun notarytool log "$SUBMISSION_ID" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER" "$OUT/notary-log.json" >/dev/null || true
[[ "$STATUS" == "Accepted" ]] || die "notarization $STATUS (log: $OUT/notary-log.json)"

step "Staple and check"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t install "$DMG"

MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
spctl -a -vv -t execute "$MOUNT/$APP_NAME.app" || { hdiutil detach "$MOUNT" >/dev/null; die "Gatekeeper rejected the app inside the DMG"; }
hdiutil detach "$MOUNT" >/dev/null

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Done: $DMG"
