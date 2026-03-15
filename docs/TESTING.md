# Testing

This document tracks integration and manual regression tests for release validation.

Automated test scripts:

- `scripts/test-gpg-file-chain.sh`
- `scripts/test-gpg-token-chain.sh`
- `scripts/test-pkcs11-chain.sh`

## PKCS#11 chain test

`scripts/test-pkcs11-chain.sh` runs the full PKCS#11 chain end-to-end
using a loopback LUKS2 device and the real smartcard:

```bash
sudo ./scripts/test-pkcs11-chain.sh
```

Creates a temporary LUKS volume, enrolls the card via `systemd-cryptenroll`,
then tests extract → decrypt → base64-encode → unlock.

## GPG token chain test

`scripts/test-gpg-token-chain.sh` runs the full GPG token chain end-to-end
using a loopback LUKS2 device and the real smartcard:

```bash
sudo ./scripts/test-gpg-token-chain.sh [--recipient <gpg-id>]
```

Uses `gpg-cryptenroll` to generate a random key, enroll it into a LUKS2 keyslot,
and store the GPG-encrypted blob as a `root-gpg` token in the LUKS2 header.
Then exercises the same extract → `gpg --decrypt` → `cryptsetup luksOpen` path
that the boot script uses.

`--recipient` is optional; if omitted, `gpg-cryptenroll` auto-detects the key
from the smartcard.

## GPG file chain test

`scripts/test-gpg-file-chain.sh` validates the file-based GPG workflow end-to-end.

`scripts/test-gpg-file-chain.sh` runs the full GPG key file chain end-to-end
using a loopback LUKS2 device and the real smartcard:

```bash
sudo ./scripts/test-gpg-file-chain.sh [--recipient <gpg-id>]
```

Uses `gpg-cryptenroll file:<path> <luks-device>` to generate a random key and write it
as a GPG-encrypted file, enrolling it into a LUKS2 keyslot. Then exercises the
same `gpg --decrypt` → `cryptsetup luksOpen` path that the boot script uses for
the "GPG key file in crypttab field 3" workflow (as opposed to the LUKS2 token
workflow tested by `test-gpg-token-chain.sh`).

Run as root (`sudo`) with the actual smartcard inserted.
Cleanup (loopback device, temp files) is automatic on exit.

# manual tests

Run these tests after development to validate full boot behavior. Reboots are
required. Remove test files/tokens/keys from the LUKS device and reboot after
each scenario.

## baseline

1. If luks-root-smartcard is installed, uninstall it.
1. Use stock cryptsetup to encrypt the root volume.
1. Boot with passphrase unlock.
1. Configure smartcard unlock using keyscript and encrypted key file.
1. Install luks-root-smartcard and verify stock boot still works.

## luks-root-smartcard

These tests require updates to crypttab. Specifically, remove keyscript and use
`none` for field 3.

1. gpg-cryptenroll file workflow decrypts with smartcard.
1. gpg-cryptenroll file workflow falls back to passphrase.
1. gpg-cryptenroll token:auto workflow falls back to passphrase.
1. gpg-cryptenroll token:auto workflow decrypts with smartcard.
1. gpg-cryptenroll token workflow with explicit slot override.
1. systemd-cryptenroll PKCS#11 workflow falls back to passphrase.
1. systemd-cryptenroll PKCS#11 workflow decrypts with smartcard.
