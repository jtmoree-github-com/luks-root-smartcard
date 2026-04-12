# luks-root-smartcard-tools

**Smartcard-based LUKS root unlock for Debian/Ubuntu initramfs**

Smartcard integration with root LUKS drives can be complex.  This script integrates smartcard setup and boot with initramfs and LUKS.  Multiple workflows are supported.

- [TPM2 workflow](#quick-start-tpm2) (systemd-tpm2)
- [FIDO2 workflow](#quick-start-fido2) (systemd-fido2)
- [PKCS#11 workflow](#quick-start-systemd-pkcs11) (systemd-pkcs11)
- GPG workflow ([gpg-token](#quick-start-gpg-token) token or [GPG key file](#quick-start-gpg-key-file))
- [Post-boot drive workflow](#quick-start-mount-token-based-drive-after-boot) (gpg-cryptopen / gpg-cryptmount)

Since systemd is not available during boot on many systems this systemd workflow boots systemd based luks2 smartcard integration without systemd in the initrd.  This may use a TPM or other types of tokens created by systemd-cryptenroll.  

The gpg workflow supports the traditional encrypted key file on disk from stock debian/ubuntu and storing the encrypted key in a luks2 header token.

## How it works

At boot, separate `local-top` scripts handle each workflow:

1. Reads `/etc/crypttab` to find the root mapping/device.
1. `00-smartcard-root-tpm2` handles *systemd-tpm2* tokens found in the LUKS2 header.
1. `05-smartcard-root-fido2` handles *systemd-fido2* tokens found in the LUKS2 header.
1. `10-smartcard-root-pkcs11` handles *systemd-pkcs11* tokens found in the LUKS2 header.
1. `20-smartcard-root-gpg` handles *gpg-token* tokens found in the LUKS2 header.
1. All scripts run at boot; each script attempts only its own workflow.
1. Each script detects card/token, decrypts key material, and opens root.
1. Falls back to passphrase prompt if token decrypt fails.

## What the package installs

| Path | Purpose |
|------|---------|
| /usr/share/initramfs-tools/hooks/smartcard-root-pkcs11 | Initramfs hook for PKCS#11 workflow (pkcs11-tool, pcscd, CCID stack, base64 helpers) |
| /usr/share/initramfs-tools/hooks/smartcard-root-gpg | Initramfs hook for GPG workflow (gpg, scdaemon — no pcscd; scdaemon uses its built-in CCID driver) |
| /usr/share/initramfs-tools/hooks/smartcard-root-fido2 | Initramfs hook for FIDO2 workflow (systemd-fido2 cryptsetup token plugin, libfido2, HID drivers) |
| /usr/share/initramfs-tools/hooks/smartcard-root-tpm2 | Initramfs hook for TPM2 workflow (systemd-tpm2 cryptsetup token plugin and TPM drivers) |
| /usr/share/initramfs-tools/scripts/local-top/05-smartcard-root-fido2 | Boot script for systemd-fido2 token unlock via cryptsetup token plugin |
| /usr/share/initramfs-tools/scripts/local-top/10-smartcard-root-pkcs11 | Boot script for systemd-pkcs11 token decrypt + base64 transform |
| /usr/share/initramfs-tools/scripts/local-top/10-smartcard-root-pkcs11 | Boot script for systemd-pkcs11 token decrypt + base64 transform |
| /usr/share/initramfs-tools/scripts/local-top/20-smartcard-root-gpg | Boot script for gpg-token token decrypt or GPG keyfile decrypt |
| /usr/share/initramfs-tools/scripts/local-top/00-smartcard-root-tpm2 | Boot script for systemd-tpm2 token unlock via cryptsetup token plugin |
| /usr/share/initramfs-tools/scripts/local-bottom/smartcard-root | Teardown — kills pcscd and cleans up sensitive files |
| /usr/sbin/gpg-cryptenroll | Helper to generate and store GPG-encrypted key material |
| /usr/sbin/gpg-cryptopen | Open any LUKS2 volume after boot using a GPG smartcard |
| /usr/sbin/gpg-cryptmount | Open and mount known LUKS2 volumes after boot for the active user |

## Supported key types

| Type | Enroll Via | Decrypt method |
|------|------------|----------------|
| systemd-pkcs11 LUKS2 token | systemd-cryptenroll | `pkcs11-tool --decrypt --mechanism RSA-PKCS` + base64 |
| systemd-fido2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-fido2` |
| systemd-tpm2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-tpm2` |
| gpg-token LUKS2 token | gpg-cryptenroll | `gpg --decrypt` via scdaemon |
| GPG key file | gpg-cryptenroll | `gpg --decrypt` via scdaemon |

## Prerequisites

### Setup

- A smartcard with an RSA or OpenPGP key or a TPM2 device
- *pcscd*, *opensc-pkcs11*, *libccid* (for PKCS#11 path)
- *gnupg*, *scdaemon* (for GPG path)
- *libfido2* and a FIDO2 authenticator exposed as */dev/hidraw** (for FIDO2 path)
- *systemd-cryptsetup* with the *systemd-tpm2* token plugin (for TPM2 path)
- *systemd-cryptsetup* with the *systemd-fido2* token plugin (for FIDO2 path)
- For *systemd-pkcs11* tokens: enroll with *systemd-cryptenroll --pkcs11-token-uri=...*
- For *systemd-fido2* tokens: enroll with *systemd-cryptenroll --fido2-device=auto ...*
- For *systemd-tpm2* tokens: enroll with *systemd-cryptenroll --tpm2-device=auto ...*
- For *gpg-token* tokens: enroll with *gpg-cryptenroll token:auto ...*

### Boot

- A smartcard with an RSA or OpenPGP key or a TPM2 device
- *pcscd*, *opensc-pkcs11*, *libccid* (for PKCS#11 path)
- *gnupg*, *scdaemon* (for GPG path)
- *libfido2* and a FIDO2 authenticator exposed as */dev/hidraw** (for FIDO2 path)

## crypttab setup

Field 3 in crypttab can still be used for stock keyfile workflows. Token workflows in this package are token-driven: the scripts inspect the root LUKS2 header and run whenever matching tokens are present.

Recommended token-mode workflow is `none` for field 3.  Anything else may yield confusing messages and conflicts:

GPG key file workflow (stock debian/ubuntu):

```
root_crypt UUID=<uuid> /boot/root.key.gpg luks
```

token workflow:

```
root_crypt UUID=<uuid> none luks
```

## Smartcard expectation trigger

Interactive smartcard expectation is controlled by token presence on the root LUKS2 device:

- If a *systemd-tpm2* token exists, TPM2 handling runs.
- If a *systemd-fido2* token exists, FIDO2 handling runs.
- If a *systemd-pkcs11* token exists, PKCS#11 smartcard handling runs.
- If a *gpg-token* token exists, GPG token smartcard handling runs.
- If no matching token exists for a workflow, that workflow exits quietly (no prompt).

When a matching smartcard token exists but no smartcard is detected, the user is prompted to either:

- insert the smartcard and continue token unlock, or
- bypass smartcard and fall back to passphrase unlock.

When matching tokens exist, workflows attempt unlock and on failure continue to the next workflow before passphrase fallback.

## Post-boot naming and mount conventions

- Default mapper name: `luks-<uuid>`
- Explicit `--name` always overrides the default
- `gpg-cryptmount` first checks `/etc/crypttab` when a name is provided

Default mount-point selection in `gpg-cryptmount` (first usable):

1. `/run/media/<user>/<mapper>`
1. `/media/<user>/<mapper>`
1. `/home/<user>/mnt/<mapper>`

This runtime fallback avoids hardcoding a distro: some Linux flavors prefer
`/media/<user>` (common on Debian/Ubuntu desktops), while many others prefer
`/run/media/<user>` (common on Fedora/RHEL/Arch/openSUSE). If neither is
available, `~/mnt` is always available as a user-owned fallback.

## Quick start (FIDO2)

```bash
# Enroll FIDO2-based unlock (prompts for LUKS passphrase and token touch/PIN as needed)
sudo systemd-cryptenroll --fido2-device=auto /dev/<luks-device>

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (systemd-pkcs11)

```bash
# Enroll the smartcard (prompts for LUKS passphrase and card PIN)
sudo systemd-cryptenroll --pkcs11-token-uri="auto" /dev/<luks-device>

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (TPM2)

```bash
# Enroll TPM2-based unlock against PCR 7
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/<luks-device>

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (GPG token)

```bash
# Find your root mapping details
root_src="$(findmnt -n -o SOURCE /)"
name="${root_src#/dev/mapper/}"

# Enroll a GPG-encrypted key and store it as a LUKS2 token
sudo gpg-cryptenroll token:auto /dev/<root-luks-device> --recipient auto --keyslot auto

# Export your public key for the initramfs
gpg --export <recipient> >/etc/cryptsetup-initramfs/pubring.gpg

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (GPG key file)

The file-based workflow uses Debian's stock `decrypt_gnupg-sc` keyscript
to decrypt the key file with the smartcard at boot.  Our `local-top` script
is not involved.  This example shows how gpg-cryptenroll assists with setting up for the stock process.

```bash
# Find your root mapping details
root_src="$(findmnt -n -o SOURCE /)"
name="${root_src#/dev/mapper/}"

# Enroll a GPG-encrypted key file
sudo gpg-cryptenroll file:/boot/root.key.gpg /dev/<root-luks-device> --recipient auto --keyslot auto

# Export your public key for the initramfs
gpg --export <recipient> >/etc/cryptsetup-initramfs/pubring.gpg

# Set crypttab: key file path + keyscript=decrypt_gnupg-sc
# (edit /etc/crypttab so the line reads:)
#   <name> UUID=<uuid> /boot/root.key.gpg luks,keyscript=decrypt_gnupg-sc

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (mount token based drive after boot)

```bash
# Enroll on the drive (same as root — creates a gpg-token in the LUKS2 header)
sudo gpg-cryptenroll token:auto /dev/<data-drive>

# Later, after boot, unlock it with the smartcard
sudo gpg-cryptopen /dev/<data-drive>
# Opens as /dev/mapper/luks-<uuid> by default.

# Or unlock and mount in one step (recommended for desktop users)
sudo gpg-cryptmount /dev/<data-drive>
# Accepts either a device spec or a /etc/crypttab name.

# Use a key file stored on disk instead of a LUKS2 token
sudo gpg-cryptopen /dev/<data-drive> --key-spec file:/etc/keys/data-drive.gpg

# Mount with explicit key file and mount point
sudo gpg-cryptmount /dev/<data-drive> --key-spec file:/etc/keys/data-drive.gpg --mount-point /home/$USER/mnt/data
```

## Build

```bash
cd luks-root-smartcard
./scripts/build-deb.sh
```

Build Launchpad-ready source artifacts and rotate top changelog entry for a target Ubuntu series:

```bash
./scripts/build-ppa-source.sh --series noble --ppa-owner jtmoree --ppa-name security-tools
```

For the current development series (questing), switch the series:

```bash
./scripts/build-ppa-source.sh --series questing --ppa-rev 1 --ppa-owner jtmoree --ppa-name security-tools
```

For the last LTS, use `lts` (currently maps to noble):

```bash
./scripts/build-ppa-source.sh --series lts --ppa-rev 2 --ppa-owner jtmoree --ppa-name security-tools
```

You can change what `lts` maps to in your local config (useful when the next
LTS is released):

```bash
# Example: switch lts alias to the next LTS when it becomes available
LUKS_LTS_SERIES=<new-lts-codename>
LUKS_LTS_SERIES_NUM=26.04
```

For Jammy, switch the series:

```bash
./scripts/build-ppa-source.sh --series jammy --ppa-rev 2 --ppa-owner jtmoree --ppa-name security-tools
```

Set Launchpad defaults once so you do not need to pass owner/name every time:

```bash
mkdir -p ~/.config/luks-root-smartcard
cat > ~/.config/luks-root-smartcard/ppa.env <<'EOF'
LUKS_PPA_OWNER=jtmoree
LUKS_PPA_NAME=security-tools
LUKS_DEBSIGN_KEYID=<your-gpg-keyid-or-fingerprint>
LUKS_LTS_SERIES=noble
LUKS_LTS_SERIES_NUM=24.04
EOF
```

After that, `--ppa-owner` and `--ppa-name` become optional:

```bash
./scripts/build-ppa-source.sh --series noble
```

If multiple secret keys exist, you can override the signer key per run:

```bash
./scripts/build-ppa-source.sh --series noble --sign-key <your-gpg-keyid-or-fingerprint>
```

If your local signing key is not configured yet, build unsigned source artifacts for preflight checks:

```bash
./scripts/build-ppa-source.sh --series noble --unsigned
```

Use the optional bump flag to increment patch version before building:

```bash
./scripts/build-deb.sh bump
```

The `.deb` is produced in the parent directory.

## Testing

Automated integration scripts are in `scripts/`:

- `scripts/test-pkcs11-chain.sh`
- `scripts/test-fido2-chain.sh`
- `scripts/test-gpg-token-chain.sh`
- `scripts/test-gpg-file-chain.sh`

Manual regression checklist and test flow are in `docs/TESTING.md`.
