# Examples

This file contains the common setup examples and quick-start commands. For prerequisites, boot behavior, and package internals, see [SETUP.md](SETUP.md). For package builds and release prep, see [BUILD.md](BUILD.md).

Use a `dev` variable in the examples below. Set the luks2 root device as the value of the variable before running these.

```bash
dev="/dev/nvmen0p1"
```

## Stock Debian/Ubuntu GPG key file

This is the Debian-managed stock GPG key-file workflow: the encrypted key stays on disk and is decrypted in initramfs with the system's `decrypt_gnupg-sc` keyscript. The gpg-cryptenroll utility from this package can assist with setup.

```bash
# Find your root mapping details
# Enroll a GPG-encrypted key file in the stock Debian/Ubuntu style
sudo gpg-cryptenroll file:/boot/root.key.gpg "$dev" --recipient auto --keyslot auto

# Export your public key for the initramfs
gpg --export <recipient> >/etc/cryptsetup-initramfs/pubring.gpg

# Set crypttab: stock Debian/Ubuntu key file + keyscript=decrypt_gnupg-sc
# (edit /etc/crypttab so the line reads:)
#   <name> UUID=<uuid> /boot/root.key.gpg luks,keyscript=decrypt_gnupg-sc

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## FIDO2

```bash
# Enroll FIDO2-based unlock (prompts for LUKS passphrase and token touch/PIN as needed)
sudo systemd-cryptenroll --fido2-device=auto "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## systemd-pkcs11

```bash
# Enroll the smartcard (prompts for LUKS passphrase and card PIN)
sudo systemd-cryptenroll --pkcs11-token-uri="auto" "$dev"

#if multiple keys found and it fails try setting a specific key
pkcs11-tool --list-slots
# pick one and set in a variable
uri=pkcs11:model=PKCS%2315%20emulated;manufacturer=ZeitControl;serial=000500001234;token=OpenPGP%20card%20%28User%20PIN%20%28sig%29%29
sudo systemd-cryptenroll --pkcs11-token-uri="$uri" "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## TPM2

```bash
# Enroll TPM2-based unlock against PCR 7
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## GPG token

```bash
# Find your root mapping details
# Enroll a GPG-encrypted key and store it as a LUKS2 token
sudo gpg-cryptenroll token:auto "$dev" --recipient auto --keyslot auto

# Export your public key for the initramfs
gpg --export <recipient> >/etc/cryptsetup-initramfs/pubring.gpg

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Mount token-based drive after boot

```bash
# Enroll on the drive (same as root — creates a gpg-token in the LUKS2 header)
sudo gpg-cryptenroll token:auto "$dev"

# Later, after boot, unlock it with the smartcard
sudo gpg-cryptopen "$dev"
# Opens as /dev/mapper/luks-<uuid> by default.

# Or unlock and mount in one step (recommended for desktop users)
sudo gpg-cryptmount "$dev"
# Accepts either a device spec or a /etc/crypttab name.

# Use a key file stored on disk instead of a LUKS2 token
sudo gpg-cryptopen "$dev" --key-spec file:/etc/keys/data-drive.gpg

# Mount with explicit key file and mount point
sudo gpg-cryptmount "$dev" --key-spec file:/etc/keys/data-drive.gpg --mount-point /home/$USER/mnt/data
```
