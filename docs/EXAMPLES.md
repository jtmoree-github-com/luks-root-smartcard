# Examples

This file contains the common setup examples and quick-start commands. For prerequisites, boot behavior, and package internals, see [SETUP.md](SETUP.md). For package builds and release prep, see [BUILD.md](BUILD.md).

Use a `dev` variable in the examples below. Set the luks2 root device as the value of the variable before running these.

```bash
dev="/dev/nvmen0p1"
```

## Stock Debian/Ubuntu GPG key file

This is the Debian-managed stock GPG key-file workflow: the encrypted key stays on disk and is decrypted in initramfs with the system's `decrypt_gnupg-sc` keyscript. The gpg-cryptenroll utility from this package can assist with setup.

### enroll

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

### remove

```bash
# Inspect keyslots and remove the slot that was enrolled for this key file
sudo cryptsetup luksDump "$dev"
sudo cryptsetup luksKillSlot "$dev" <slot>

# Remove files used by this workflow
sudo rm -f /boot/root.key.gpg /etc/cryptsetup-initramfs/pubring.gpg

# Revert /etc/crypttab to your preferred non-keyfile unlock method

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## FIDO2

### enroll

```bash
# Enroll FIDO2-based unlock (prompts for LUKS passphrase and token touch/PIN as needed)
sudo systemd-cryptenroll --fido2-device=auto "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

### remove

```bash
# Remove all FIDO2 enrollments from this LUKS device
sudo systemd-cryptenroll --wipe-slot=fido2 "$dev"

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## systemd-pkcs11

### enroll

```bash
# Enroll the smartcard (prompts for LUKS passphrase and card PIN)
sudo systemd-cryptenroll --pkcs11-token-uri="auto" "$dev"

# If it fails with "Provided URI matches multiple public keys, refusing.",
# your URI is too broad (one key URI can be a subset of another).
# 1) List token-level candidates:
sudo COLUMNS=240 systemd-cryptenroll --pkcs11-token-uri=list "$dev"
token='pkcs11:...'
# 2) Pick the token URI you want and list object-level URIs for it:
p11tool --list-all --detailed-url --only-urls $token
# 3) Copy one full object URI (prefer one with id= and object=) and enroll with it:
uri='pkcs11:...;id=%03;object=Authentication%20key;type=public'
sudo systemd-cryptenroll --pkcs11-token-uri="$uri" "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

### remove

```bash
# Remove all PKCS#11 enrollments from this LUKS device
sudo systemd-cryptenroll --wipe-slot=pkcs11 "$dev"

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## TPM2

### enroll

```bash
# Enroll TPM2-based unlock against PCR 7
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$dev"

# Recommended: set crypttab field 3 to none for token mode
# (edit /etc/crypttab so the line reads: <name> UUID=<uuid> none luks)

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

### remove

```bash
# Remove all TPM2 enrollments from this LUKS device
sudo systemd-cryptenroll --wipe-slot=tpm2 "$dev"

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## GPG token

### enroll

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

### remove

```bash
# List token ids and locate type "gpg-token"
sudo cryptsetup token list "$dev"
sudo cryptsetup token export --token-id <token-id> "$dev"

# Remove the token metadata
sudo cryptsetup token remove --token-id <token-id> "$dev"

# Remove the associated keyslot used by that token
sudo cryptsetup luksKillSlot "$dev" <slot>

# Rebuild initramfs
sudo update-initramfs -u -k "$(uname -r)"
```

## Mount token-based drive after boot

### enroll

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

### remove

```bash
# Remove token mode (find gpg-token id, remove token, then remove its keyslot)
sudo cryptsetup token list "$dev"
sudo cryptsetup token export --token-id <token-id> "$dev"
sudo cryptsetup token remove --token-id <token-id> "$dev"
sudo cryptsetup luksKillSlot "$dev" <slot>

# If you enrolled file-based unlocks for this drive, remove those slots too
sudo cryptsetup luksDump "$dev"
sudo cryptsetup luksKillSlot "$dev" <slot>

# Optional: remove local encrypted key file
sudo rm -f /etc/keys/data-drive.gpg
```
