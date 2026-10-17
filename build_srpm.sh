#!/bin/bash
set -euo pipefail

ZOTERO_REPO="${1:?Usage: $0 REPO TAG OUTDIR}"
ZOTERO_TAG="${2:?}"
OUTDIR="${3:?}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Clone upstream source
git clone --branch "$ZOTERO_TAG" --depth 1 "$ZOTERO_REPO" zotero-src
cd zotero-src
git lfs install
git lfs pull
git submodule update --init --recursive --depth 1

# Ensure all submodule working trees are checked out
git submodule foreach --recursive 'git checkout .'

# Guard: dir_build's CLI is not a stable upstream interface (10.0.0 dropped -q).
# Fail here, in the SRPM phase, instead of after one wasted failed build per
# enabled chroot. Keep this list in sync with %build in zotero-nightly.spec.
DIR_BUILD_OPTS=$(sed -n 's/.*while getopts "\([^"]*\)".*/\1/p' app/scripts/dir_build | head -1)
for opt in p a f; do
    case "$DIR_BUILD_OPTS" in
        *"$opt"*) ;;
        *)
            echo "ERROR: app/scripts/dir_build no longer accepts -$opt" >&2
            echo "       getopts is \"$DIR_BUILD_OPTS\" -- update %build in zotero-nightly.spec" >&2
            sed -n '/^Usage:/,/^DONE/p' app/scripts/dir_build >&2 || true
            exit 1
            ;;
    esac
done

# Capture version info
COMMIT=$(git rev-parse HEAD)
SHORT_COMMIT=$(git rev-parse --short=9 HEAD)
DATE=$(date +%Y%m%d)
# Extract version from the tag name (e.g. "8.0.5" from tag "8.0.5")
VERSION=$(echo "$ZOTERO_TAG" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+')
if [ -z "$VERSION" ]; then
    # Fallback: parse from version file
    VERSION=$(grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' version)
fi

echo "Building: ${VERSION} tag=${ZOTERO_TAG} commit=${SHORT_COMMIT}"

# Build JavaScript (arch-independent)
npm ci --no-audit --no-fund
npm run build

# Pre-download Firefox ESR runtime for Linux (both arches)
app/scripts/fetch_xulrunner -p l -a x64
app/scripts/fetch_xulrunner -p l -a arm64

# Save commit hash for use in rpmbuild (where .git is absent)
echo "$COMMIT" > .commit_hash

# Resolve symlinks in build/ so we can remove node_modules
# npm run build creates symlinks pointing into node_modules/
rsync -aL --delete build/ build.resolved/
rm -rf build
mv build.resolved build

# Remove build-only artifacts to shrink tarball
rm -rf node_modules

cd ..

# Create source tarball
TARBALL_NAME="zotero-nightly-${VERSION}"
mv zotero-src "$TARBALL_NAME"
tar --create --xz \
    --exclude='.git' \
    --exclude='.github' \
    -f "${TARBALL_NAME}-${DATE}git${SHORT_COMMIT}.tar.xz" \
    "${TARBALL_NAME}/"

# Generate spec with resolved version info
sed \
    -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@DATE@/${DATE}/g" \
    -e "s/@SHORT_COMMIT@/${SHORT_COMMIT}/g" \
    -e "s/@COMMIT@/${COMMIT}/g" \
    "$SCRIPT_DIR/zotero-nightly.spec" > zotero-nightly-resolved.spec

# Build SRPM
rpmbuild -bs zotero-nightly-resolved.spec \
    --define "_sourcedir $(pwd)" \
    --define "_srcrpmdir ${OUTDIR}"

echo "SRPM created in ${OUTDIR}"
