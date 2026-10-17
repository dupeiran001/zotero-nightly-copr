#!/bin/bash
# End-user check: enable the COPR repo the way `dnf copr enable` does, install
# the package in a clean container, verify the payload, and start the app.
#
#   ./verify-install.sh                 # Fedora 43, x86_64
#   ./verify-install.sh 44
#   ./verify-install.sh rawhide
#   CONTAINER_TOOL=docker ./verify-install.sh 43     # e.g. inside GitHub Actions
#   CHROOT=epel-9-x86_64 IMAGE=quay.io/centos/centos:stream9 ./verify-install.sh
#
# The launch step runs as a non-root user and prints the version string, so a
# build that packages the wrong tree, or that cannot start against its own
# dependencies, fails here instead of on someone's desktop.
set -uo pipefail

REL="${1:-43}"
CONTAINER_TOOL="${CONTAINER_TOOL:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"
CHROOT="${CHROOT:-fedora-${REL}-x86_64}"
IMAGE="${IMAGE:-quay.io/fedora/fedora:${REL}}"
PROJECT="dupeiran/zotero-nightly"
REPO="${PROJECT#*/}"
REPO_URL="https://copr.fedorainfracloud.org/coprs/${PROJECT}/repo/${CHROOT}/${REPO}-${CHROOT}.repo"
# optional: VERSION-RELEASE that must end up installed, e.g.
#   EXPECT=10.0.6-0.20261017git536244c27 ./verify-install.sh 43
EXPECT="${EXPECT:-}"

echo "== ${CONTAINER_TOOL} ${IMAGE} <- ${CHROOT}${EXPECT:+ (expect ${EXPECT})}"

"${CONTAINER_TOOL}" run -i --rm "${IMAGE}" bash -s -- "${CHROOT}" "${REPO_URL}" "${EXPECT}" <<'IN_CONTAINER'
set -euo pipefail
chroot_name="$1"; repo_url="$2"; expect="${3:-}"
# this is what 'dnf copr enable' writes into /etc/yum.repos.d
curl -sSL -o /etc/yum.repos.d/_copr_zotero-nightly.repo "$repo_url"
head -4 /etc/yum.repos.d/_copr_zotero-nightly.repo

# EPEL images need the EPEL repositories themselves before our repo is usable
case "$chroot_name" in
    epel-8-*) dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm ;;
    epel-9-*) dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm ;;
    epel-10-*) dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm ;;
esac

dnf -y install zotero-nightly
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}  installed size %{SIZE} bytes\n' zotero-nightly

if [ -n "$expect" ]; then
    installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}' zotero-nightly)
    case "$installed" in
        "$expect"*) echo "version check ok: $installed provides $expect" ;;
        *) echo "FAIL: the repo serves $installed, expected $expect"; exit 1 ;;
    esac
fi

# rpm -V must stay silent: every file the RPM owns is present and unmodified
if [ -n "$(rpm -V zotero-nightly)" ]; then
    echo "FAIL: rpm -V reports differences"
    rpm -V zotero-nightly
    exit 1
fi
ls -l /usr/bin/zotero-nightly /usr/lib/zotero-nightly/zotero
find /usr/lib/zotero-nightly -maxdepth 2 -name application.ini -o -maxdepth 2 -name platform.ini

if command -v dnf >/dev/null; then
    # util-linux provides su in recent Fedora images; shadow-utils alone is not
    # enough, and the minimal Fedora containers ship neither.
    dnf -y install desktop-file-utils util-linux shadow-utils >/dev/null 2>&1 || true
fi
desktop-file-validate /usr/share/applications/zotero-nightly.desktop
echo "desktop file valid"

run_as_nobody() {
    if command -v runuser >/dev/null 2>&1; then
        runuser -u nobody -- "$@"
    elif command -v su >/dev/null 2>&1; then
        su -s /bin/bash nobody -c "$(printf '%q ' "$@")"
    else
        echo "FAIL: the image has neither runuser nor su to drop privileges"
        exit 1
    fi
}

echo "--- zotero --version (headless, as a non-root user)"
chmod 1777 /tmp
version=$(run_as_nobody env HOME=/tmp timeout 180 /usr/bin/zotero-nightly --version 2>&1 | tail -3)
echo "$version"
case "$version" in
    *Zotero*) ;;
    *) echo "FAIL: the packaged app did not report a Zotero version"; exit 1 ;;
esac
echo "INSTALL CHECK PASSED for $chroot_name"
IN_CONTAINER
