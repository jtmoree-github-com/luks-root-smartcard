# luks-root-smartcard-tools

**Smartcard-based LUKS root unlock for Debian/Ubuntu initramfs**

This project integrates smartcard setup and boot with initramfs and LUKS so encrypted root volumes can be unlocked with hardware instead of a passphrase and without requiring systemd in initrd.

Supported workflows include:

- stock Debian/Ubuntu GPG key-file workflow
- systemd TPM2 token unlock
- systemd FIDO2 token unlock
- systemd PKCS#11 smartcard token unlock
- GPG token unlock
- Post-boot unlock and mount for secondary drives

## Additional notes

- Systemd is not available during boot on many systems but systemd luks2 tokens are well supported.
- Not all systems have a TPM, and even when they do, systemd-tpm2 may require hardware features that are not available.
- The GPG workflow may leverage the stock Debian/Ubuntu encrypted key-file on disk or the LUKS2 header token workflow, which avoids keeping a key file on a drive.

## Documentation

- [Setup and internals](docs/SETUP.md)
- [Examples](docs/EXAMPLES.md)
- [Build and packaging](docs/BUILD.md)
- [Testing](docs/TESTING.md)
