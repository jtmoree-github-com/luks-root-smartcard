# PKCS#11 certificate helper for libpam-p11

`scripts/p11cert.sh` generates a short-lived self-signed certificate from a
PKCS#11 private key and appends it to `~/.eid/authorized_certificates` for
local smartcard setup workflows.

Runtime requirements:

- `p11tool`
- `openssl`

Behavior:

- accepts an explicit `pkcs11:` URL or auto-selects a key using `p11tool`
- fails fast if the required commands are missing
- writes `~/.eid/authorized_certificates` atomically
- skips appending a duplicate certificate for the same PKCS#11 public key