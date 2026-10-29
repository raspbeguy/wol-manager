#!/bin/sh
# Build the wol-manager apk against a pinned OpenWrt SDK.
#
# Inputs (env):
#   SDK_URL     full URL of the SDK tarball (.tar.zst)         [required]
#   SDK_SHA256  expected sha256 of that tarball                [required]
#   SDK_DIR     extract/cache location (default: $REPO/.sdk)
# Output:
#   prints the built apk's absolute path as the last stdout line; also writes
#   `apk=<path>` to $GITHUB_OUTPUT when running under GitHub Actions.
set -eu

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SDK_DIR=${SDK_DIR:-"$REPO_DIR/.sdk"}
: "${SDK_URL:?SDK_URL required}"
: "${SDK_SHA256:?SDK_SHA256 required}"

TARBALL=$(basename "$SDK_URL")
TMP=${TMPDIR:-/tmp}

if [ ! -d "$SDK_DIR/staging_dir" ]; then
	echo "Downloading SDK: $SDK_URL"
	mkdir -p "$SDK_DIR"
	curl -fsSL -o "$TMP/$TARBALL" "$SDK_URL"
	echo "$SDK_SHA256  $TMP/$TARBALL" | sha256sum -c -
	tar --use-compress-program=unzstd -xf "$TMP/$TARBALL" -C "$SDK_DIR" --strip-components=1
	rm -f "$TMP/$TARBALL"
fi

cd "$SDK_DIR"

./scripts/feeds update -a >/dev/null 2>&1 || ./scripts/feeds update -a

# The runtime dependencies come from the feeds; they have to be known packages
# for wol-manager to be selectable.
./scripts/feeds install etherwake uhttpd ucode >/dev/null

# Copy rather than symlink: the SDK lives inside the repo by default, and a
# link back to the repo root would make the package scan recurse into the SDK.
DEST=package/wol-manager
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$REPO_DIR/Makefile" "$REPO_DIR/VERSION" "$REPO_DIR/LICENSE" "$REPO_DIR/files" "$DEST/"

grep -q '^CONFIG_PACKAGE_wol-manager=y' .config 2>/dev/null \
	|| echo 'CONFIG_PACKAGE_wol-manager=y' >> .config
make defconfig >/dev/null

if ! grep -q '^CONFIG_PACKAGE_wol-manager=y' .config; then
	echo "ERROR: wol-manager could not be selected (dependency unresolved)." >&2
	exit 1
fi

# A cached SDK keeps the apk of the previous build in bin/; remove it so the
# lookup below cannot return a stale file.
find bin -name 'wol-manager-*.apk' -delete 2>/dev/null || true

make package/wol-manager/compile V=s

APK=$(find bin -name 'wol-manager-*.apk' | sort -V | tail -1)
[ -n "$APK" ] || { echo "ERROR: no wol-manager apk produced" >&2; exit 1; }
APK_ABS="$SDK_DIR/$APK"

echo "Built: $APK_ABS"
sha256sum "$APK_ABS"
[ -n "${GITHUB_OUTPUT:-}" ] && echo "apk=$APK_ABS" >> "$GITHUB_OUTPUT"
echo "$APK_ABS"
