# Setup and internals

This guide covers prerequisites, boot-time behavior, and package internals for the supported workflows. For copy-paste examples, see [EXAMPLES.md](EXAMPLES.md). For building the package or preparing Launchpad source artifacts, see [BUILD.md](BUILD.md).

## Supported key types

| Type | Enroll via | Decrypt method |
|------|------------|----------------|
| stock Debian/Ubuntu GPG key file | gpg-cryptenroll | Debian `decrypt_gnupg-sc` keyscript via scdaemon |
| systemd-pkcs11 LUKS2 token | systemd-cryptenroll | `pkcs11-tool --decrypt --mechanism RSA-PKCS` + base64 |
| systemd-fido2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-fido2` |
| systemd-tpm2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-tpm2` |
| gpg-token LUKS2 token | gpg-cryptenroll | `gpg --decrypt` via scdaemon |

## Choose a workflow

TL;DR;  Examples

- [Debian/Ubuntu GPG key file](EXAMPLES.md#stock-debianubuntu-gpg-key-file) for the Debian-managed GPG key-file workflow using `decrypt_gnupg-sc`.
- [FIDO2](EXAMPLES.md#fido2) for a FIDO2 authenticator
- [TPM2](EXAMPLES.md#tpm2) for a TPM-backed LUKS2 token
- [PKCS#11](EXAMPLES.md#systemd-pkcs11) for a smartcard-backed PKCS#11 token
- [GPG token](EXAMPLES.md#gpg-token) for a GPG smartcard token in the LUKS2 header
- [Post-boot mount](EXAMPLES.md#mount-token-based-drive-after-boot) for unlocking and mounting a secondary drive later

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

## crypttab setup

Field 3 in crypttab can still be used for the stock Debian/Ubuntu keyfile workflow. Token workflows in this package are token-driven: the scripts inspect the root LUKS2 header and run whenever matching tokens are present.

Stock Debian/Ubuntu GPG key file workflow:

```text
root_crypt UUID=<uuid> /boot/root.key.gpg luks
```

The other workflows are token based. Recommended token-mode workflow is `none` for field 3. Anything else may yield confusing messages and conflicts:

```text
root_crypt UUID=<uuid> none
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

## Initramfs asset inclusion

By default the package copies the runtime assets for all workflows (TPM2, FIDO2, PKCS#11, GPG) into the initramfs, whether or not a matching token is currently enrolled. This lets you enroll a new token type later and have it work after a normal `update-initramfs -u`, with no extra setup.

The decision is made at initramfs generation time (`update-initramfs` / `mkinitramfs`), not at package build time, and is controlled by a post-install toggle at `/etc/luks-root-smartcard/initramfs.conf`:

```text
# all      - include every workflow's assets (default)
# detected - include only assets for tokens in the root LUKS2 header
SMARTCARD_INITRAMFS_INCLUDE=all
```

Change the value and rebuild:

```bash
sudo update-initramfs -u -k "$(uname -r)"
```

For a one-off override without editing the file:

```bash
sudo SMARTCARD_INITRAMFS_INCLUDE=detected update-initramfs -u -k "$(uname -r)"
```

This setting only controls which assets are bundled. Each boot script still activates only when its own token type is present, so including everything does not force unused workflows to run.

## Post-boot naming and mount conventions

- Default mapper name: `luks-<uuid>`
- Explicit `--name` always overrides the default
- `gpg-cryptmount` first checks `/etc/crypttab` when a name is provided

Default mount-point selection in `gpg-cryptmount` (first usable):

1. `/run/media/<user>/<mapper>`
1. `/media/<user>/<mapper>`
1. `/home/<user>/mnt/<mapper>`

This runtime fallback avoids hardcoding a distro: some Linux flavors prefer `/media/<user>` (common on Debian/Ubuntu desktops), while many others prefer `/run/media/<user>` (common on Fedora/RHEL/Arch/openSUSE). If neither is available, `~/mnt` is always available as a user-owned fallback.

