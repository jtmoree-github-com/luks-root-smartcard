---
name: update-ppa
description: "Build and upload a PPA source package for luks-root-smartcard-tools. Use when: publishing to Launchpad PPA, releasing a new PPA version, building ppa source, uploading to ppa, bumping ppa version, targeting a new Ubuntu series for the PPA (resolute, questing, noble, jammy)."
argument-hint: "<series> [--ppa-rev <n>]"
---

# Update PPA

Builds a signed Launchpad PPA source package and prints the `dput` upload command.

## Key Files

- `scripts/build-ppa-source.sh` — rewrites `debian/changelog` top entry for the target series and runs `dpkg-buildpackage -S`
- `scripts/build-deb.sh --bump` — bumps the patch version in `debian/changelog` before a PPA build
- `debian/changelog` — source of truth for the package version

## Supported Series

| Series | Version |
|---|---|
| `resolute` | 26.04 |
| `questing` | 25.10 |
| `noble` / `lts` | 24.04 |
| `jammy` | 22.04 |

## Procedure

### 1. Check the current version

Read the first line of `debian/changelog` to confirm the base version. The top entry must use `unstable` or a plain series name (not a `~ppa` suffix) before building.

### 2. Bump the patch version (if releasing a new upstream version)

Ask the user whether the version should be bumped. Per user preference, **always bump the patch (3rd number) before building**. Run:

```bash
./scripts/build-deb.sh --bump
```

### 3. Build the PPA source package

```bash
./scripts/build-ppa-source.sh --series <series> --ppa-rev <n>
```

- `--series` is required. Choose from: `resolute`, `questing`, `noble`, `jammy`, `lts`
- `--ppa-rev` defaults to `1`; increment when re-uploading the same upstream version to the same series
- The script rewrites the `debian/changelog` top line to `<version>~ppa<n>~ubuntu<XX.YY>.1` and builds a signed source package

### 4. Upload to Launchpad

After the build succeeds, the script prints the exact `dput` command. Ask the user to run it:

```bash
dput ppa:<owner>/<ppa-name> ../luks-root-smartcard-tools_<version>_source.changes
```

**Do not run `dput` or `sudo` commands yourself — always ask the user to run privileged/upload commands.**

### 5. Restore changelog (if needed)

After uploading, the changelog top line still holds the `~ppa` version. If the user wants to restore the `unstable` entry for local builds, update the first line back to:

```
luks-root-smartcard-tools (<base-version>) unstable; urgency=medium
```

Or simply run the next `build-deb.sh --bump` to produce a fresh entry.

## Config File

PPA owner, PPA name, and signing key can be stored in:

```
~/.config/luks-root-smartcard/ppa.env
```

```bash
LUKS_PPA_OWNER=jtmoree
LUKS_PPA_NAME=<ppa-name>
LUKS_DEBSIGN_KEYID=<keyid-or-fingerprint>
```

## User Preferences

- Always bump the 3rd version number (patch) before building
- Never run `sudo` — ask the user to run privileged commands
- Use GitHub no-reply email in `debian/changelog`: `JT <jtmoree@users.noreply.github.com>`
