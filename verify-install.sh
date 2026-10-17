#!/bin/bash
# End-user install check: enable the COPR repo exactly the way
# `dnf copr enable` does, install, and start the app.
#   ./verify-install.sh [43|44|...]
set -uo pipefail
REL="${1:-43}"
REPO_URL="https://copr.fedorainfracloud.org/coprs/dupeiran/zotero-nightly/repo/fedora-$REL-x86_64/zotero-nightly-fedora-$REL-x86_64.repo"

podman run --rm quay.io/fedora/fedora:"$REL" bash -c "
set -x
# this is what 'dnf copr enable' writes into /etc/yum.repos.d
curl -sSL -o /etc/yum.repos.d/_copr_zotero-nightly.repo '$REPO_URL'
cat /etc/yum.repos.d/_copr_zotero-nightly.repo | head -4
dnf -y install zotero-nightly 2>&1 | tail -3
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH} installed size %{SIZE} bytes\n' zotero-nightly
rpm -V zotero-nightly | head -5
ls -l /usr/bin/zotero-nightly /usr/lib/zotero-nightly/zotero
find /usr/lib/zotero-nightly -maxdepth 2 -name 'application.ini' -o -maxdepth 2 -name 'platform.ini' | head -4
grep -rE '^(Version|ID|Name)=' /usr/lib/zotero-nightly/app/application.ini /usr/lib/zotero-nightly/platform.ini 2>/dev/null | head -6
dnf -y install desktop-file-utils shadow-utils util-linux >/dev/null 2>&1
desktop-file-validate /usr/share/applications/zotero-nightly.desktop && echo 'desktop file valid'
echo '--- zotero --version (headless, as non-root)'
chmod 1777 /tmp
su -s /bin/bash nobody -c 'HOME=/tmp timeout 180 /usr/bin/zotero-nightly --version' 2>&1 | tail -8
"
