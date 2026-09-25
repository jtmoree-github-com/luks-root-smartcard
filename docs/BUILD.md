# Build and packaging

This guide covers local package builds and Launchpad-ready source packaging. For setup prerequisites and workflow behavior, see [SETUP.md](SETUP.md). For quick-start examples, see [EXAMPLES.md](EXAMPLES.md).

## Local build

From the repository root:

```bash
cd luks-root-smartcard
./scripts/build-deb.sh
```

This produces the Debian package in the parent directory.

To bump the patch version before building:

```bash
./scripts/build-deb.sh bump
```

## Local build dependencies

Before building the Debian package locally, install the required build tools for your distro:

```bash
sudo ./scripts/build-deps.sh
```

This helper installs the base build packages on Debian/Ubuntu and Fedora/RHEL-like systems.

## Launchpad source builds

Build Launchpad-ready source artifacts and rotate the top changelog entry for a target Ubuntu series:

```bash
PPAOWNER=jtmoree
PPANAME=security-tools
```

```bash
./scripts/build-ppa-source.sh --series noble --ppa-owner "$PPAOWNER" --ppa-name "$PPANAME"
```

For the current development series (questing), switch the series:

```bash
./scripts/build-ppa-source.sh --series questing --ppa-rev 1 --ppa-owner "$PPAOWNER" --ppa-name "$PPANAME"
```

For the current LTS, use `lts` (currently maps to resolute):

```bash
./scripts/build-ppa-source.sh --series lts --ppa-rev 2 --ppa-owner "$PPAOWNER" --ppa-name "$PPANAME"
```

You can change what `lts` maps to in your local config if you need to target a newer or older LTS release:

```bash
# Example: switch lts alias to the new long-term support target
LUKS_LTS_SERIES=resolute
LUKS_LTS_SERIES_NUM=26.04
```

For Jammy, switch the series:

```bash
./scripts/build-ppa-source.sh --series jammy --ppa-rev 2 --ppa-owner "$PPAOWNER" --ppa-name "$PPANAME"
```

Set Launchpad defaults once so you do not need to pass owner/name every time:

```bash
mkdir -p ~/.config/luks-root-smartcard
cat > ~/.config/luks-root-smartcard/ppa.env <<'EOF'
LUKS_PPA_OWNER=jtmoree
LUKS_PPA_NAME=security-tools
LUKS_DEBSIGN_KEYID=<your-gpg-keyid-or-fingerprint>
LUKS_LTS_SERIES=resolute
LUKS_LTS_SERIES_NUM=26.04
EOF
```

For smart-card backed keys, set `LUKS_DEBSIGN_KEYID` to the full fingerprint of the card key you use for signing. This avoids email/UID auto-selection issues when the changelog maintainer address differs from the key UID.

After that, `--ppa-owner` and `--ppa-name` become optional:

```bash
./scripts/build-ppa-source.sh --series resolute
```

If multiple secret keys exist, you can override the signer key per run:

```bash
./scripts/build-ppa-source.sh --series noble --sign-key <your-gpg-keyid-or-fingerprint>
```

If your local signing key is not configured yet, build unsigned source artifacts for preflight checks:

```bash
./scripts/build-ppa-source.sh --series noble --unsigned
```

## PPA signing with smart cards

When your primary certifying key is not stored locally (for example, `sec#` with `ssb>` card subkeys), adding a new UID/email with `gpg --edit-key adduid` may fail because GnuPG requires secret-key material for certification.

In that case, sign PPA source builds by explicitly selecting the signer key fingerprint:

```bash
./scripts/build-ppa-source.sh --series resolute --sign-key <full-key-fingerprint>
```

Or set it once in `~/.config/luks-root-smartcard/ppa.env`:

```bash
LUKS_DEBSIGN_KEYID=<full-key-fingerprint>
```

Optional global fallback for devscripts/debsign:

```bash
DEBSIGN_KEYID=<full-key-fingerprint>
```

`build-ppa-source.sh` also reads `DEBSIGN_KEYID` from `~/.devscripts` when `--sign-key`, `LUKS_DEBSIGN_KEYID`, and `DEBSIGN_KEYID` are not already set in the environment/config.

### Troubleshooting: `No secret key` for GitHub noreply email

If you see:

```text
gpg: skipped "JT Moree <jtmoree@users.noreply.github.com>": No secret key
```

it usually means GnuPG tried to sign using the changelog maintainer identity instead of your smart-card key ID. Force the key with `--sign-key` or `LUKS_DEBSIGN_KEYID` as shown above.

You can verify signing works with the selected key before running the PPA build:

```bash
echo test | gpg --local-user <full-key-fingerprint> --clearsign >/tmp/gpg-sign-test.asc
```

## Package layout

| Path | Purpose |
|------|---------|
| /usr/share/initramfs-tools/hooks/smartcard-root-pkcs11 | Initramfs hook for PKCS#11 workflow (pkcs11-tool, pcscd, CCID stack, base64 helpers) |
| /usr/share/initramfs-tools/hooks/smartcard-root-gpg | Initramfs hook for GPG workflow (gpg, scdaemon — no pcscd; scdaemon uses its built-in CCID driver) |
| /usr/share/initramfs-tools/hooks/smartcard-root-fido2 | Initramfs hook for FIDO2 workflow (systemd-fido2 cryptsetup token plugin, libfido2, HID drivers) |
| /usr/share/initramfs-tools/hooks/smartcard-root-tpm2 | Initramfs hook for TPM2 workflow (systemd-tpm2 cryptsetup token plugin and TPM drivers) |
| /usr/share/initramfs-tools/scripts/local-top/05-smartcard-root-fido2 | Boot script for systemd-fido2 token unlock via cryptsetup token plugin |
| /usr/share/initramfs-tools/scripts/local-top/10-smartcard-root-pkcs11 | Boot script for systemd-pkcs11 token decrypt + base64 transform |
| /usr/share/initramfs-tools/scripts/local-top/20-smartcard-root-gpg | Boot script for gpg-token token decrypt or GPG keyfile decrypt |
| /usr/share/initramfs-tools/scripts/local-top/00-smartcard-root-tpm2 | Boot script for systemd-tpm2 token unlock via cryptsetup token plugin |
| /usr/share/initramfs-tools/scripts/local-bottom/smartcard-root | Teardown — kills pcscd and cleans up sensitive files |
| /usr/sbin/gpg-cryptenroll | Helper to generate and store GPG-encrypted key material |
| /usr/sbin/gpg-cryptopen | Open any LUKS2 volume after boot using a GPG smartcard |
| /usr/sbin/gpg-cryptmount | Open and mount known LUKS2 volumes after boot for the active user |

## Notes

- The package is produced in the parent directory of the repository.
- Use the release helper when you want to prepare PPA-ready source packages for a target Ubuntu series.
- The build scripts are the operational interface for both local builds and release packaging.
