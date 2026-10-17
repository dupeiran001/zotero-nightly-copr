#!/bin/bash
# Rebuild the most recent published source package in a clean Fedora container,
# with %build patched to the dir_build flags currently in zotero-nightly.spec.
#
# Cheap way to prove a build works before triggering a real COPR build (one per
# enabled chroot), and to pre-check a new Fedora release.
#
#   ./verify-rpm-build.sh                      # Fedora 43, newest published srpm
#   FEDORA=44 ./verify-rpm-build.sh            # a newer release
#   FEDORA=rawhide ./verify-rpm-build.sh
#   SRPM_URL=https://download.copr.fedorainfracloud.org/results/.../x.src.rpm \
#       ./verify-rpm-build.sh                  # a specific build
#
# Only the native arch of the container is exercised; aarch64 still needs a real
# aarch64 builder (COPR has them).
set -euo pipefail

COPR_OWNER="${COPR_OWNER:-dupeiran}"
COPR_PROJECT="${COPR_PROJECT:-zotero-nightly}"
FEDORA="${FEDORA:-43}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/.cache/zotero-nightly-verify/fedora-$FEDORA}"
API="https://copr.fedorainfracloud.org/api_3"

# The dir_build invocation actually under test, taken from the spec template so
# this script can never drift from what a real build does.
X64_CMD=$(grep -m1 'dir_build -p l -a x64' "$REPO_DIR/zotero-nightly.spec")
ARM_CMD=$(grep -m1 'dir_build -p l -a arm64' "$REPO_DIR/zotero-nightly.spec")
echo "testing: $X64_CMD"

if [ -z "${SRPM_URL:-}" ]; then
    echo "looking up newest published srpm for $COPR_OWNER/$COPR_PROJECT"
    SRPM_URL=$(curl -fsSL "$API/build/list?ownername=$COPR_OWNER&projectname=$COPR_PROJECT&limit=1&order_type=DESC" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["source_package"]["url"])')
fi
echo "source package: $SRPM_URL"

mkdir -p "$WORK"
if [ ! -s "$WORK/source.src.rpm" ]; then
    curl -fL --retry 3 -o "$WORK/source.src.rpm.part" "$SRPM_URL"
    mv "$WORK/source.src.rpm.part" "$WORK/source.src.rpm"
fi

cat > "$WORK/inside.sh" <<'CONTAINER'
set -eux -o pipefail
dnf -y install --setopt=install_weak_deps=False \
    rpm-build git-core perl python3 rsync zip unzip findutils \
    desktop-file-utils openssl cpio tar gzip which
rm -rf /b
mkdir -p /b
cd /b
# COPR builds SRPMs with a flat payload: no SOURCES/ or SPECS/ subdirectories.
rpm2cpio /w/source.src.rpm | cpio -idm
spec=$(echo /b/*.spec)
ls -l /b

# Replace the upstream-published %build flags with the ones under test.
before=$(grep -c '^[[:space:]]*app/scripts/dir_build' "$spec")
sed -i -E "s@^[[:space:]]*app/scripts/dir_build -p l -a x64.*\$@$X64_CMD@" "$spec"
sed -i -E "s@^[[:space:]]*app/scripts/dir_build -p l -a arm64.*\$@$ARM_CMD@" "$spec"
after=$(grep -c "^[[:space:]]*$X64_CMD\$" "$spec")
test "$before" -eq 2 -a "$after" -eq 1   # both branches present, x64 one patched
grep -n 'app/scripts/dir_build' "$spec"

rpmbuild -bb --define "_topdir /b" --define "_sourcedir /b" "$spec"
rpm=$(ls /b/RPMS/*/zotero-nightly-*.rpm)
mkdir -p /w/out
rm -f /w/out/*.rpm
cp $rpm /w/out/
ls -lh /w/out/
# The runtime Requires must still resolve in this Fedora release, or the package
# is uninstallable there even though it built. --assumeno prints the transaction
# and exits non-zero by design, so assert on the summary line instead.
deps=$(dnf -y install --assumeno "/w/out/$(basename $rpm)" 2>&1) || true
echo "$deps" | tail -4
if ! echo "$deps" | grep -qE "Installing:?[[:space:]]+[0-9]+[[:space:]]+[Pp]ackage"; then
    echo "ERROR: runtime dependencies do not resolve; last 40 lines:"
    echo "$deps" | tail -40
    exit 1
fi
echo "runtime dependencies resolve"
CONTAINER

podman run --rm \
    -e X64_CMD="$X64_CMD" -e ARM_CMD="$ARM_CMD" \
    -v "$WORK:/w:z" \
    "quay.io/fedora/fedora:$FEDORA" \
    bash /w/inside.sh 2>&1 | tee "$WORK/build-fedora-$FEDORA.log"

echo "log: $WORK/build-fedora-$FEDORA.log"
