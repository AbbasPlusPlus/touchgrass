#!/usr/bin/env bash
#
# TouchGrass release: build → stamp → sign → zip → checksum → appcast → GitHub.
#
#   Support/release.sh 0.2.0 ["Release notes."]
#   make release VERSION=0.2.0
#
# Environment:
#   BUILD=<n>        CFBundleVersion. Default: current appcast build + 1.
#   NOTES="…"        Release notes. Default: the second positional argument, else the subject
#                    lines of the commits since the previous tag.
#   DRY_RUN=1        Build, zip, hash and write dist/appcast.json — then stop. No network writes.
#   ALLOW_DIRTY=1    Skip the clean-tree check (dry runs only; never ship an untracked build).
#
# The zip is the artefact users get. Its SHA-256 is the whole security model: TouchGrass is
# ad-hoc signed with no Developer ID, so the client trusts HTTPS to a repo only we can push to,
# plus a digest that the download must match byte for byte before anything is replaced.
set -euo pipefail

APP="TouchGrass"
RELEASES_REPO="AbbasPlusPlus/touchgrass-releases"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APPDIR="$ROOT/build.noindex/$APP.app"
PLIST="$APPDIR/Contents/Info.plist"
ZIP="$DIST/$APP.zip"
APPCAST="$DIST/appcast.json"

DRY_RUN="${DRY_RUN:-0}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- arguments

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: Support/release.sh <version> [notes]   (e.g. 0.2.0)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] \
  || die "version must look like 1.2.3 or 1.2.3-beta.1, got \"$VERSION\""
TAG="v$VERSION"

# ---------------------------------------------------------------- preflight

command -v /usr/libexec/PlistBuddy >/dev/null || die "PlistBuddy is missing"
if [ "$DRY_RUN" != "1" ]; then
  command -v gh >/dev/null || die "gh (GitHub CLI) is required; brew install gh"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"
fi

if [ "$ALLOW_DIRTY" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  die "working tree is dirty — commit or stash first (ALLOW_DIRTY=1 to override on a dry run)"
fi

if [ "$DRY_RUN" != "1" ] && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists locally"
fi

# ---------------------------------------------------------------- build number

if [ -z "${BUILD:-}" ]; then
  CURRENT_APPCAST="$(curl -fsSL --max-time 20 \
    "https://raw.githubusercontent.com/$RELEASES_REPO/main/appcast.json" 2>/dev/null || true)"
  if [ -n "$CURRENT_APPCAST" ]; then
    BUILD="$(printf '%s' "$CURRENT_APPCAST" \
      | /usr/bin/python3 -c 'import json,sys; print(int(json.load(sys.stdin).get("build",0))+1)' \
      2>/dev/null || echo "")"
  fi
  BUILD="${BUILD:-1}"
fi
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "BUILD must be an integer, got \"$BUILD\""

# ---------------------------------------------------------------- notes

NOTES="${NOTES:-${2:-}}"
if [ -z "$NOTES" ]; then
  PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [ -n "$PREV_TAG" ]; then
    NOTES="$(git log --no-merges --pretty='- %s' "$PREV_TAG..HEAD" | head -20)"
  fi
  NOTES="${NOTES:-Maintenance release.}"
fi

step "$APP $VERSION (build $BUILD)"

# ---------------------------------------------------------------- build

step "Building a clean release bundle"
rm -rf "$ROOT/build" "$DIST"
mkdir -p "$DIST"
make bundle
[ -d "$APPDIR" ] || die "make bundle did not produce $APPDIR"

# ---------------------------------------------------------------- stamp

step "Stamping version into Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "26.0")"

# Keep the tracked plist in step so a plain `make run` reports the same version.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Support/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$ROOT/Support/Info.plist"

# ---------------------------------------------------------------- sign

step "Re-signing (ad-hoc) after the plist edit"
# Editing Info.plist invalidates the signature that `make bundle` applied, so this is required,
# not belt-and-braces: an unsigned or stale-signed bundle fails the client's codesign check.
codesign --force --sign - --entitlements "$ROOT/Support/TouchGrass.entitlements" "$APPDIR" \
  || codesign --force --sign - "$APPDIR"
codesign --verify --strict --deep "$APPDIR" || die "the freshly signed bundle does not verify"
xattr -cr "$APPDIR" 2>/dev/null || true

# ---------------------------------------------------------------- package

step "Zipping"
# --keepParent so the archive expands to TouchGrass.app, which is what the client looks for.
ditto -c -k --keepParent --sequesterRsrc "$APPDIR" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(stat -f%z "$ZIP")"

step "Writing appcast.json"
URL="https://github.com/$RELEASES_REPO/releases/download/$TAG/$APP.zip"
VERSION="$VERSION" BUILD="$BUILD" URL="$URL" SHA="$SHA" NOTES="$NOTES" MIN_OS="$MIN_OS" \
/usr/bin/python3 - "$APPCAST" <<'PY'
import json, os, sys
doc = {
    "version": os.environ["VERSION"],
    "build": int(os.environ["BUILD"]),
    "url": os.environ["URL"],
    "sha256": os.environ["SHA"],
    "notes": os.environ["NOTES"],
    "minOS": os.environ["MIN_OS"],
}
with open(sys.argv[1], "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

printf '\n'
cat "$APPCAST"
printf '\n%s  (%s bytes)\n\n' "$ZIP" "$SIZE"

if [ "$DRY_RUN" = "1" ]; then
  step "DRY_RUN=1 — stopping before the tag, the GitHub release and the appcast push."
  git checkout -- "$ROOT/Support/Info.plist" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------- publish

step "Tagging $TAG"
git add Support/Info.plist
# The stamp may already be committed from a previous attempt — a no-op commit must not abort.
git diff --cached --quiet || git commit -m "Release $VERSION (build $BUILD)"
git tag -a "$TAG" -m "$APP $VERSION"
git push origin HEAD
git push origin "$TAG"

step "Creating the GitHub release on $RELEASES_REPO"
gh release create "$TAG" "$ZIP" \
  --repo "$RELEASES_REPO" \
  --title "$APP $VERSION" \
  --notes "$NOTES"

step "Pushing appcast.json to $RELEASES_REPO"
# Clone shallowly into a temp dir: the appcast repo is not a submodule and must not become one.
WORK="$(mktemp -d /tmp/touchgrass-appcast.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$RELEASES_REPO" "$WORK/repo" -- --depth 1
cp "$APPCAST" "$WORK/repo/appcast.json"
git -C "$WORK/repo" add appcast.json
if git -C "$WORK/repo" diff --cached --quiet; then
  step "appcast.json unchanged — nothing to push"
else
  git -C "$WORK/repo" commit -m "$APP $VERSION (build $BUILD)"
  git -C "$WORK/repo" push
fi

step "Bumping the Homebrew cask"
TAP_WORK="$(mktemp -d /tmp/touchgrass-tap.XXXXXX)"
gh repo clone AbbasPlusPlus/homebrew-touchgrass "$TAP_WORK/tap" -- --depth 1
CASK="$TAP_WORK/tap/Casks/touchgrass.rb"
SHA256="$(python3 -c "import json;print(json.load(open('$APPCAST'))['sha256'])")"
sed -i '' "s|^  version \".*\"|  version \"$VERSION\"|" "$CASK"
sed -i '' "s|^  sha256 \".*\"|  sha256 \"$SHA256\"|" "$CASK"
git -C "$TAP_WORK/tap" add Casks/touchgrass.rb
if git -C "$TAP_WORK/tap" diff --cached --quiet; then
  step "cask unchanged"
else
  git -C "$TAP_WORK/tap" commit -m "touchgrass $VERSION"
  git -C "$TAP_WORK/tap" push
fi
rm -rf "$TAP_WORK"

step "Released $APP $VERSION"
printf 'Clients will see it within 24 h, or immediately via Settings ▸ General ▸ Check Now.\n'
