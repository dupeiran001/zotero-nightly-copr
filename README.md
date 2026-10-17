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

### How often does it build?

The workflow runs every day at 06:00 UTC (GitHub may start a scheduled run a few
hours late), but it only triggers a COPR build when the newest upstream *release
tag* differs from `.last-built-tag`. Zotero tags a release about once a week, so
that is how often this repo publishes — despite the name, it is a repackaged
release tracker, not a per-commit nightly. A day with no new tag does nothing
except the install test of whatever is published.

If you want a real nightly, compare the commit at the tip of upstream `main`
(`git ls-remote https://github.com/zotero/zotero.git HEAD`) instead of the newest
tag and store it in a second file; every upstream merge would then produce a
build, at the cost of one 8-chroot build per day and the occasional upstream break
— which is exactly what the failure mail is for.

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

### Extra chroots, including EPEL

`copr-cli list-chroots` is the authoritative active list. On 2026-10-17 it
offered `fedora-{43,44,45}-{x86_64,aarch64,i386,ppc64le,riscv64,s390x}`,
`fedora-rawhide-*`, `fedora-eln-*` and `epel-{8,9,10}-{x86_64,aarch64,ppc64le,s390x}`
(Fedora 42 is gone apart from `fedora-42-riscv64`). To add EPEL:

```bash
copr-cli modify dupeiran/zotero-nightly \
    --chroot epel-9-x86_64  --chroot epel-9-aarch64 \
    --chroot epel-10-x86_64 --chroot epel-10-aarch64
```

`--chroot` is repeatable and only adds; nothing is removed. Nothing in this repo
would change — `.copr/Makefile` and the spec are already distro-agnostic — but EPEL
has not been exercised here: the SRPM runs `npm ci` and `npm run build`, so the
Node.js that EPEL ships decides whether the build works. Try one chroot first
(`--chroot epel-9-x86_64`) and watch the build. EPEL 8 is the riskiest: the
bundled Firefox ESR 140 is newer than what RHEL 8 era libraries target.

To install from an EPEL chroot the repo name carries the chroot, e.g.
`copr-cli` users point dnf at
`.../coprs/dupeiran/zotero-nightly/repo/epel-9-x86_64/zotero-nightly-epel-9-x86_64.repo`.

### Expired (EOL) chroot repositories

On *Settings → Repositories* COPR lists chroots whose Fedora release reached end
of life and offers **Extend** or **Expire**. `Expire` schedules that chroot's
*repository* for deletion — the frontend flashes "Repository for `<chroot>` is
scheduled to be removed. If you changed your mind, click 'Extend' to revert your
decision" (`OutdatedChrootsLogic.expire` in `coprs_general.py`). It does not
cancel or rebuild anything, and it only touches that one EOL chroot. `Extend`
keeps the repository for another `DELETE_EOL_CHROOTS_AFTER` period. Expired
repositories still resolve until they are pruned — `fedora-42-x86_64` still
served its last successful build (`9.0.5`) after the chroot had been disabled.

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

After a build succeeds, `verify-install.sh` takes the end-user path in a
container: it writes the real COPR `.repo` file (so the GPG key is used the way
`dnf copr enable` uses it), installs, checks the version that landed, runs
`rpm -V` and `desktop-file-validate`, and starts the app as a non-root user:

```bash
./verify-install.sh 43
EXPECT=10.0.6-0.20261017git536244c27 ./verify-install.sh 44   # assert what the repo serves
CONTAINER_TOOL=docker ./verify-install.sh rawhide             # GitHub runners have docker
CHROOT=epel-9-x86_64 IMAGE=quay.io/centos/centos:stream9 ./verify-install.sh
```

The script fails — non-zero exit, `FAIL:` line — when the installed version is
not the expected one, when `rpm -V` reports anything, when the desktop file does
not validate, or when `zotero --version` does not answer as an ordinary user.

## Build health

The daily workflow does all of this in one job:

1. compares the newest upstream tag with `.last-built-tag`;
2. if it changed (or `force_build` is ticked) records the newest COPR build id,
   POSTs the webhook, and waits up to 5 h for that build to finish;
3. reads back the published version, failing with builder-log excerpts if the
   newest build is not `succeeded`;
4. installs the published RPM in clean Fedora containers (`FEDORA_CHECKS`, x86_64)
   and starts it, exactly like `verify-install.sh` above;
5. only then records the new tag in `.last-built-tag`.

Because the tag is written last, a failed build leaves the tag alone and the next
daily run retries the same release instead of skipping it as already built.

| secret | needed for | notes |
| --- | --- | --- |
| `COPR_WEBHOOK_URL` | triggering the build | the project's own hook, see below; no token involved |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS` | failure mail | optional; without them the workflow just skips the mail step |
| `MAIL_TO`, `MAIL_FROM` | failure mail | `MAIL_TO` is required for a mail to be sent |

`tools/notify.py` sends the mail with plain `smtplib` (implicit TLS on 465,
STARTTLS on 587) and refuses to send credentials over a connection without TLS.
Set `SMTP_PORT=25` plus `SMTP_INSECURE=1` only if your relay really is plaintext
on the local network.

Check the newest build by hand with:

```bash
python3 tools/copr_build_status.py                    # newest build, read-only
python3 tools/copr_build_status.py --summary          # '<id>\t<state>\t<nvr>\t<chroots>'
python3 tools/copr_build_status.py --after-id 11162888 --timeout 7200   # watch the next one
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

This bit us once: `-q` disappeared in Zotero 10.0.0, so every release from 10.0.2
to 10.0.6 (Sep–Oct 2026) failed in all chroots while the repo kept serving 9.0.6.
The repo only catches up with a successful build, so check
`tools/copr_build_status.py` after a fix rather than assuming the next nightly
will pick it up — the nightly only fires on a *new* upstream tag.
