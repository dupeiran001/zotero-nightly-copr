# zotero-nightly-copr

COPR packaging for [Zotero](https://www.zotero.org/) on Fedora Linux (x86_64 and aarch64), built from upstream source.

## Install

```bash
sudo dnf copr enable dupeiran/zotero-nightly
sudo dnf install zotero-nightly
```

## How it works

A daily GitHub Actions cron job checks [zotero/zotero](https://github.com/zotero/zotero) for new tagged releases. When a new tag is found, it triggers a COPR webhook that kicks off a source build:

1. Clones `zotero/zotero` at the latest release tag
2. Builds JavaScript with `npm run build`
3. Fetches the Firefox ESR runtime for Linux (x86_64 + aarch64)
4. Assembles the application via upstream `dir_build`
5. Packages the result as an RPM

## Package details

- **Name:** `zotero-nightly`
- **Install path:** `/usr/lib/zotero-nightly/`
- **Binary:** `zotero-nightly`
- **License:** AGPL-3.0-or-later
