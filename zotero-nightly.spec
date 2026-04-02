%global forgeurl    https://github.com/zotero/zotero
%global date        @DATE@
%global shortcommit @SHORT_COMMIT@
%global commit      @COMMIT@

Name:           zotero-nightly
Version:        @VERSION@
Release:        0.%{date}git%{shortcommit}%{?dist}
Summary:        Zotero reference manager (nightly build from source)
License:        AGPL-3.0-or-later
URL:            %{forgeurl}
ExclusiveArch:  x86_64 aarch64

# Binaries are pre-compiled Firefox ESR; no debug info available
%global debug_package %{nil}

Source0:        zotero-nightly-%{version}-%{date}git%{shortcommit}.tar.xz
Source10:       zotero-nightly.desktop
Source11:       zotero.sh

BuildRequires:  git-core
BuildRequires:  perl
BuildRequires:  python3
BuildRequires:  rsync
BuildRequires:  zip
BuildRequires:  unzip
BuildRequires:  findutils
BuildRequires:  desktop-file-utils

Requires:       gtk3
Requires:       dbus-libs
Requires:       nss
Requires:       nspr
Requires:       alsa-lib
Requires:       libXt
Requires:       libX11
Requires:       libXcomposite
Requires:       libXdamage
Requires:       libXfixes
Requires:       libXrandr
Requires:       mesa-libgbm
Requires:       pango
Requires:       cairo
Requires:       glib2

Provides:       zotero = %{version}
Conflicts:      zotero

%description
Zotero is a free, easy-to-use tool to help you collect, organize, annotate,
cite, and share research. This package provides nightly builds from the
upstream Git source.

%prep
%setup -q -n zotero-nightly-%{version}

# Recreate minimal .git so dir_build's `git rev-parse --short HEAD` works
git init -q
git checkout -q -b main
echo "ref: refs/heads/main" > .git/HEAD
cp .commit_hash .git/refs/heads/main

%build
%ifarch x86_64
app/scripts/dir_build -p l -a x64 -q
%endif
%ifarch aarch64
app/scripts/dir_build -p l -a arm64 -q
%endif

%install
install -d %{buildroot}/usr/lib/zotero-nightly

%ifarch x86_64
cp -a app/staging/Zotero_linux-x86_64/* %{buildroot}/usr/lib/zotero-nightly/
%endif
%ifarch aarch64
cp -a app/staging/Zotero_linux-arm64/* %{buildroot}/usr/lib/zotero-nightly/
%endif

install -d %{buildroot}%{_bindir}
install -m 0755 %{SOURCE11} %{buildroot}%{_bindir}/zotero-nightly

install -d %{buildroot}%{_datadir}/applications
desktop-file-install \
    --dir=%{buildroot}%{_datadir}/applications \
    %{SOURCE10}

install -d %{buildroot}%{_datadir}/icons/hicolor/128x128/apps
install -m 0644 %{buildroot}/usr/lib/zotero-nightly/icons/icon128.png \
    %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/zotero-nightly.png

install -d %{buildroot}%{_datadir}/icons/hicolor/64x64/apps
install -m 0644 %{buildroot}/usr/lib/zotero-nightly/icons/icon64.png \
    %{buildroot}%{_datadir}/icons/hicolor/64x64/apps/zotero-nightly.png

install -d %{buildroot}%{_datadir}/icons/hicolor/32x32/apps
install -m 0644 %{buildroot}/usr/lib/zotero-nightly/icons/icon32.png \
    %{buildroot}%{_datadir}/icons/hicolor/32x32/apps/zotero-nightly.png

%files
%license COPYING
%{_bindir}/zotero-nightly
%{_datadir}/applications/zotero-nightly.desktop
%{_datadir}/icons/hicolor/*/apps/zotero-nightly.png
/usr/lib/zotero-nightly/

%changelog
* Thu Apr 02 2026 Dupeiran - @VERSION@-0.@DATE@git@SHORT_COMMIT@
- Nightly build from upstream source
