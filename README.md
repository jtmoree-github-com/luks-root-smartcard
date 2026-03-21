# luks-root-smartcard-tools

**Smartcard-based LUKS root unlock for Debian/Ubuntu initramfs**

Smartcard integration with root LUKS drives can be complex.  This script assists setup with initramfs and LUKS using either systemd implementation of luks2 smartcard or gpg based workflows.  The gpg workflow supports the traditional encrypted key file on disk from stock debian/ubuntu and storing the encrypted key in a luks2 header token.

- PKCS#11 workflow (`systemd-pkcs11`)
- GPG workflow (`root-gpg` token or GPG key file)
- TPM2 workflow (`systemd-tpm2`)

*Note that debian/ubuntu do not ship systemd in the boot process.  I have implemented support for systemd-pkcs11 and systemd-tpm2 without using systemd to allow booting root volumes encrypted with systemd-cryptenroll using initramfs-tools.*

## How it works

At boot, separate `local-top` scripts handle each workflow:

1. Reads `/etc/crypttab` to find the root mapping and key spec.
2. `00-smartcard-root-pkcs11` handles PKCS#11 tokens found in the LUKS2 header.
3. `00-smartcard-root-gpg` handles `root-gpg` tokens or GPG keyfile paths.
4. `00-smartcard-root-tpm2` handles `systemd-tpm2` tokens found in the LUKS2 header.
5. All three scripts run at boot; each attempts only its own workflow and exits if the volume is already open.
6. The selected script decrypts/unseals key material and opens root.
7. Falls back to passphrase prompt if decrypt/unseal fails.
## What the package installs

| Path | Purpose |
|------|---------|
| `/usr/share/initramfs-tools/hooks/smartcard-root-pkcs11` | Initramfs hook for PKCS#11 workflow (`pkcs11-tool`, `pcscd`, CCID stack, base64 helpers) |
| `/usr/share/initramfs-tools/hooks/smartcard-root-gpg` | Initramfs hook for GPG workflow (`gpg`, `scdaemon` — no pcscd; scdaemon uses its built-in CCID driver) |
| `/usr/share/initramfs-tools/hooks/smartcard-root-tpm2` | Initramfs hook for TPM2 workflow (`tpm2-tools`, TSS2 libraries, TPM kernel modules) |
| `/usr/share/initramfs-tools/scripts/local-top/00-smartcard-root-pkcs11` | Boot script for PKCS#11 token decrypt + base64 transform |
| `/usr/share/initramfs-tools/scripts/local-top/00-smartcard-root-gpg` | Boot script for `root-gpg` token decrypt or GPG keyfile decrypt |
| `/usr/share/initramfs-tools/scripts/local-top/00-smartcard-root-tpm2` | Boot script for TPM2 token unseal via `tpm2_unseal` with PCR policy |
| `/usr/share/initramfs-tools/scripts/local-bottom/smartcard-root` | Teardown — kills `pcscd` and cleans up sensitive files |
| `/usr/sbin/gpg-cryptenroll` | Helper to generate and store GPG-encrypted key material |

## Supported key types

| Type | Storage | Decrypt method |
|------|---------|----------------|
| `systemd-pkcs11` | LUKS2 token (enrolled via `systemd-cryptenroll`) | `pkcs11-tool --decrypt --mechanism RSA-PKCS` + base64 |
| `root-gpg` | LUKS2 token (enrolled via `gpg-cryptenroll`) | `gpg --decrypt` via scdaemon |
| GPG key file | File path in crypttab field 3 | `gpg --decrypt` via scdaemon |
| `systemd-tpm2` | LUKS2 token (enrolled via `systemd-cryptenroll`) | `tpm2_unseal` with PCR policy via `tpm2-tools` |

## Prerequisites

- A smartcard with an RSA or OpenPGP key (tested with Purism Librem Key)
- `pcscd`, `opensc-pkcs11`, `libccid` (for PKCS#11 path)
- `gnupg`, `scdaemon` (for GPG path)
- For `systemd-pkcs11` tokens: enroll with `systemd-cryptenroll --pkcs11-token-uri=...`
- `tpm2-tools`, libtss2, TPM2 hardware or firmware TPM (for TPM2 path)
- For `systemd-tpm2` tokens: enroll with `systemd-cryptenroll --tpm2-device=auto ...`

## crypttab setup

Stock Debian/Ubuntu use field 3 in crypttab to specify a keyfile. If a keyfile is present in field 3 both scripts do nothing and allow stock OS behavior.

To activate the features supported by these tools set field 3 to `none`.  Each workflow auto-detects its own token type from the luks2 header.

GPG key file workflow (stock):

```
root_crypt UUID=<uuid> /boot/root.key.gpg luks
```

GPG token, pkcs11, and tpm2 workflow:

```
root_crypt UUID=<uuid> none luks
```

## Quick start (systemd-tpm2)

```bash
# Enroll the TPM2 chip, binding to PCR 7 (Secure Boot state)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/<luks-device>

# Set crypttab field 3 to none
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Install tpm2-tools if not already present
sudo apt install tpm2-tools

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

The TPM2 script reads the `systemd-tpm2` LUKS2 token written by `systemd-cryptenroll`.
At boot, it recreates the TPM2 Storage Root Key (SRK) using the standard TCG ECC P-256
template, loads the sealed object, satisfies the PCR policy with current PCR values,
and calls `tpm2_unseal` to recover the LUKS key.  If PCR values have changed since
enrollment (e.g. firmware update, Secure Boot key rotation) the unseal will fail and
the boot falls back to the passphrase prompt.

**PIN support** (`--tpm2-with-pin=yes`) is not currently implemented; tokens enrolled
with a PIN will fall through to the passphrase prompt.

## Quick start (systemd-pkcs11)

```bash
# Enroll the smartcard (prompts for LUKS passphrase and card PIN)
sudo systemd-cryptenroll --pkcs11-token-uri="auto" /dev/<luks-device>
# Set crypttab field 3 to none
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (GPG token--no key file--via gpg-cryptenroll helper)

```bash
# Find your root mapping details
root_src="$(findmnt -n -o SOURCE /)"
name="${root_src#/dev/mapper/}"

# Enroll a GPG-encrypted key and store it as a LUKS2 token
sudo gpg-cryptenroll token:auto /dev/<root-luks-device> --recipient auto --keyslot auto

# Export your public key for the initramfs
gpg --export <recipient> >/etc/cryptsetup-initramfs/pubring.gpg

# Set crypttab field 3 to none
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Quick start (GPG key file via gpg-cryptenroll helper)

The file-based workflow uses Debian's stock `decrypt_gnupg-sc` keyscript
to decrypt the key file with the smartcard at boot.  Our `local-top` script
is not involved — stock cryptroot handles everything.  This example shows how gpg-cryptenroll assists with setting up for the stock process.

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

## Build

```bash
cd luks-root-smartcard
./scripts/build-deb.sh
```

Use the optional bump flag to increment patch version before building:

```bash
./scripts/build-deb.sh bump
```

The `.deb` is produced in the parent directory.

## Testing

Automated integration scripts are in `scripts/`:

- `scripts/test-pkcs11-chain.sh`
- `scripts/test-gpg-token-chain.sh`
- `scripts/test-gpg-file-chain.sh`
- `scripts/test-tpm2-chain.sh`

Manual regression checklist and test flow are in `docs/TESTING.md`.
