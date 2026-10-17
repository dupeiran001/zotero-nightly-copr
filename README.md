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

## Fedora versions

Chroots are `fedora-{43,44,45,rawhide}-{x86_64,aarch64}`. The COPR project has
**follow Fedora branching** enabled, so when COPR creates a chroot for a new
Fedora release it is added to this project automatically — nothing in this repo
pins a Fedora version, and no repo change is needed when Fedora 46, 47, … ship.

To check what a project currently builds for:

```bash
sudo dnf install copr-cli
copr-cli list-chroots                        # everything COPR offers right now
copr-cli get dupeiran/zotero-nightly         # what this project has enabled
```

If auto-enabling is ever turned off (`copr-cli modify --follow-fedora-branching
off`), re-enable it or add a release by hand with
`copr-cli modify dupeiran/zotero-nightly --chroot fedora-46-x86_64`, then confirm
with `copr-cli get`. The same settings are under project *Edit* in the web UI.

## Checking a build before triggering one

Every COPR build fans out to one build per chroot, so a bad spec costs 8 builds.
`verify-rpm-build.sh` rebuilds the newest published source package in a clean
Fedora container instead, using the `dir_build` flags currently in the spec:

```bash
./verify-rpm-build.sh                    # Fedora 43, x86_64
FEDORA=rawhide ./verify-rpm-build.sh     # pre-check the next Fedora
```

It only exercises the container's native arch; aarch64 still needs a real
aarch64 builder (COPR has one).

## Build health

The daily workflow triggers a build and then waits for it, failing if the result
is not `succeeded`. On failure it prints the builder log URLs and the error
lines from up to three chroots. Check the newest build by hand with:

```bash
python3 tools/copr_build_status.py            # read-only, no COPR token needed
```

To rebuild without waiting for a new upstream tag: **Actions → Check upstream
release → Run workflow → tick "Trigger a COPR build even if upstream has no new
tag"**. The workflow keeps the `COPR_WEBHOOK_URL` repo secret, so no token is
needed locally. That URL is the COPR project's own hook, shown under
*Settings → Integrations* on the project page
(`https://copr.fedorainfracloud.org/webhooks/<forge>/<id>/<uuid>/`); it can be
POSTed directly with `curl -X POST '<url>' -H 'Content-Type: application/json' -d '{}'`,
or replaced by a GitHub repo webhook pointing at it if you prefer push-triggered
builds. Your COPR API token (for `copr-cli`, from <https://copr.fedorainfracloud.org/api/>
into `~/.config/copr`) does the same job as `copr-cli build-package
dupeiran/zotero-nightly --name zotero-nightly`.

## Troubleshooting

**`dir_build: illegal option -- X` in `%build`.** Upstream treats the flags of
`app/scripts/dir_build` as internal: Zotero 10.0.0 dropped `-q` (quick build)
and added `-f` (force full rebuild). `build_srpm.sh` now checks the flags
against the cloned upstream before doing any work, so this fails in the SRPM
phase with the current usage instead of after 8 chroot builds. Fix `%build` in
`zotero-nightly.spec` to match, and `verify-rpm-build.sh` before pushing.
