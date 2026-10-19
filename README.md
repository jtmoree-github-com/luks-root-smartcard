# luks-root-smartcard-tools

**Smartcard-based LUKS root unlock for Debian/Ubuntu initramfs**

This project integrates smartcard setup and boot with initramfs and LUKS so encrypted root volumes can be unlocked with hardware (e.g. tpm, gpg, fido) with passphrase fallback without requiring systemd in initrd.

Your options may be constrained by your hardware and LUKS version.

## Supported workflows:

- stock Debian/Ubuntu GPG key-file workflow
- systemd TPM2 token unlock
- systemd FIDO2 token unlock
- systemd PKCS#11 smartcard token unlock
- GPG token unlock
- Post-boot unlock and mount for secondary drives

## How it works

At boot, separate `local-top` scripts detect tokens in the LUKS2 header to activate workflows:

1. `00-smartcard-root-tpm2` handles *systemd-tpm2* tokens found in the LUKS2 header.
1. `05-smartcard-root-fido2` handles *systemd-fido2* tokens found in the LUKS2 header.
1. `10-smartcard-root-pkcs11` handles *systemd-pkcs11* tokens found in the LUKS2 header.
1. `20-smartcard-root-gpg` handles *gpg-token* tokens found in the LUKS2 header.
1. By default all scripts run at boot; each script attempts only its own workflow.
1. Each script detects card/token, decrypts key material, and opens root.
1. **Falls back to stock LUKS passphrase prompt if token missing or decrypt fails.**

## Additional notes

- Systemd is not available during boot on many systems but systemd luks2 tokens are well supported after boot.  This utility bridges the boot gap for initramfs without using systemd.
- Not all systems have a TPM, and even when they do, systemd-tpm2 may require hardware features that are not available.  This utility expands the options for root decrypt.
- Multiple GPG workflows are supported including stock debian decrypt.  `gpg-cryptenroll` assists with setup.
- LUKS version 1 is only compatible with the stock debian keyfile on disk.  Tokens used by the others are a LUKS 2 feature.

## Documentation

- [Setup](docs/SETUP.md)
- [Examples](docs/EXAMPLES.md)
- [Build and packaging](docs/BUILD.md)
- [Testing](docs/TESTING.md)

## License

This project is licensed under the MIT (Expat) license. See [LICENSE](LICENSE) and [debian/copyright](debian/copyright).
