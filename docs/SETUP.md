# Setup

This guide covers prerequisites, boot-time behavior, and package internals for the supported workflows. For copy-paste examples, see [EXAMPLES.md](EXAMPLES.md). For building the package or preparing Launchpad source artifacts, see [BUILD.md](BUILD.md).

## Supported key types

| Type | Enroll via | Decrypt method | modify crypttab | Depends |
|------|------------|----------------|----------------|---------|
| stock Debian/Ubuntu GPG key file | gpg-cryptenroll | Debian `decrypt_gnupg-sc` keyscript via scdaemon | yes | public key and unlock file copied to initramfs |
| gpg-token LUKS2 token | gpg-cryptenroll | `gpg --decrypt` via scdaemon | no | public key visible to GnuPG in initramfs GNUPGHOME |
| systemd-pkcs11 LUKS2 token | systemd-cryptenroll | `pkcs11-tool --decrypt --mechanism RSA-PKCS` + base64 | no | PKCS#11 certificate/key object exposed by the card/provider |
| systemd-fido2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-fido2` | no | FIDO2 authenticator and device binding |
| systemd-tpm2 LUKS2 token | systemd-cryptenroll | `cryptsetup luksOpen --token-type systemd-tpm2` | no | TPM2 device and token metadata |

## Choose a workflow

TL;DR;  Pick the workflow you want to use which may be constrained by your available hardware.  Stock Debian does not need anything in this package but we include a utility and example to help set it up.

- [Debian/Ubuntu GPG key file](#debianubuntu-gpg-key-file-workflow-stock) for the Debian-managed GPG key-file workflow using `decrypt_gnupg-sc`.
- [FIDO2](#fido2-workflow) for a FIDO2 authenticator
- [GPG token](#gpg-token-workflow) for a GPG smartcard token in the LUKS2 header
- [PKCS#11](#pkcs11-workflow) for a smartcard-backed PKCS#11 token
- [Post-boot mount](EXAMPLES.md#mount-token-based-drive-after-boot) for unlocking and mounting a secondary drive later
- [TPM2](#tpm2-workflow) for a TPM-backed LUKS2 token

## Prerequisites

### Debian/Ubuntu GPG key file workflow (stock)

See the [stock Debian/Ubuntu GPG key file example](EXAMPLES.md#stock-debianubuntu-gpg-key-file).

#### Setup

- Install the workflow stack:
  - `sudo apt install gnupg scdaemon pcscd cryptsetup-initramfs`
- Smartcard with an OpenPGP key
- Enroll with *gpg-cryptenroll* for the key file path
- Export the recipient public key into `/etc/cryptsetup-initramfs/pubring.gpg`
- modify `/etc/crypttab`

#### Boot

- Smartcard inserted and readable by GnuPG/scdaemon
- Initramfs contains the copied public key and encrypted key file
- Debian `decrypt_gnupg-sc` keyscript can unlock the key file

### FIDO2 workflow

See the [FIDO2 example](EXAMPLES.md#fido2).

#### Setup

- Install the workflow stack:
  - `sudo apt install libfido2-1 fido2-tools`
- FIDO2 authenticator exposed as */dev/hidraw**
- Enroll with *systemd-cryptenroll --fido2-device=auto ...*

#### Boot

- FIDO2 device present and accessible in initramfs
- `cryptsetup` token plugin support available for `systemd-fido2`

### GPG token workflow

See the [GPG token example](EXAMPLES.md#gpg-token).

#### Setup

- Install the workflow stack:
  - `sudo apt install gnupg scdaemon pcscd`
- Smartcard with an OpenPGP-compatible key exposed to GnuPG
- Enroll with *gpg-cryptenroll token:auto ...*
- Ensure the matching public key is present in the user keyring and in `/etc/cryptsetup-initramfs/pubring.gpg` before the initramfs is rebuilt

#### Boot

- Smartcard inserted and readable by GnuPG/scdaemon
- `gpg --card-status` must resolve the card-backed key in the initramfs GNUPGHOME
- `pcscd` and GnuPG smartcard stack present in initramfs

### PKCS#11 workflow

See the [PKCS#11 example](EXAMPLES.md#systemd-pkcs11).

#### Setup

- Install the workflow stack:
  - `sudo apt install opensc pcscd`
- Smartcard with a usable certificate/key object exposed through PKCS#11
- Enroll with *systemd-cryptenroll --pkcs11-token-uri=...*

#### Boot

- Smartcard inserted and visible through PKCS#11
- `pkcs11-tool` can enumerate the relevant certificate/key object
- `pcscd` and the PKCS#11 provider are available in initramfs

### TPM2 workflow

See the [TPM2 example](EXAMPLES.md#tpm2).

#### Setup

- Install the workflow stack:
  - `sudo apt install systemd-cryptsetup`
- TPM2 device available to the system
- Enroll with *systemd-cryptenroll --tpm2-device=auto ...*

#### Boot

- TPM2 device present and accessible at boot
- `cryptsetup` token plugin support available for `systemd-tpm2`

## crypttab setup

Token workflows in this package are token-driven: the scripts inspect the root LUKS2 header and run whenever matching tokens are present.  Token workflows do not use crypttab.

The only workflow that uses /etc/crypttab is the stock debian *decrypt_gnu_sc*.  If you have already modified it you may want to put it back to the default.  The recommended value for token workflows is `none` for field 3.  Anything else may yield confusing messages and conflicts:

```text
root_crypt UUID=<uuid> none
```

For the stock Debian/Ubuntu GPG key file workflow field 3 in crypttab is generally set to the location of the encrypted keyfile.  Double check with debian's standard documentation.

```text
root_crypt UUID=<uuid> /boot/root.key.gpg luks
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

## Boot debug toggle (no rebuild required)

Debug logs for all initramfs workflows can be turned on/off at boot time with kernel command-line flags. This does not require rebuilding initramfs.

- Enable debug:
  - `smartcard-root.debug=1` (package-specific)
  - `rd.debug=1` (global initramfs-style flag)
- Disable debug:
  - `smartcard-root.debug=0`
  - `rd.debug=0`

When both enable and disable flags are present, the last one on the kernel command line wins.

With debug enabled, workflows emit additional traces for:

- token discovery and selector choice
- plugin/runtime dependency discovery
- smartcard device detection and wait loops
- prompt responses (skip/retry choices)
- command failures with stderr context (`gpg`, `pkcs11-tool`, `cryptsetup`)
- a final summary line with `result` and `reason` code for log scraping

Summary format:

```text
smartcard-root-<workflow>: DEBUG: summary result=<success|fallback|skip> reason=<reason-code> mapper=<name|unset> device=<path|unset>
```

For the GPG root-unlock workflow, debug lines are also mirrored into the kernel
log (`/dev/kmsg`) so you can retrieve full boot history after login even when
the initramfs console scrollback is limited:

```bash
journalctl -k -b | grep 'smartcard-root-gpg'
```

## Initramfs asset inclusion

By default the package copies the runtime assets for all workflows (TPM2, FIDO2, PKCS#11, GPG) into the initramfs, whether or not a matching token is currently enrolled. This lets you enroll a new token type later and have it work after a normal `update-initramfs -u`, with no extra setup.

For the GPG workflow, the hook always creates `/cryptroot/gnupghome` inside the initramfs so `gpg --card-status`, `gpg-agent`, and `scdaemon` have a writable homedir at boot. If `/etc/cryptsetup-initramfs/pubring.gpg` exists, its public keys are imported into that homedir during initramfs generation.

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
