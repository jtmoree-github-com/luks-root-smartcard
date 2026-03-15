#!/bin/sh
# Test the full PKCS#11 encrypt→store→extract→decrypt→unlock chain
# using a virtual (loopback) LUKS2 device + the real smartcard.
#
# Uses systemd-cryptenroll to add the token (same as real enrollment).
#
# Usage:  sudo ./scripts/test-pkcs11-chain.sh
# Cleanup is automatic on exit.

set -eu

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MAPPER_NAME="test-smartcard-$$"

cleanup() {
    set +e
    [ -n "$MAPPER_NAME" ] && cryptsetup close "$MAPPER_NAME" 2>/dev/null
    [ -n "$LOOP_DEV" ] && losetup -d "$LOOP_DEV" 2>/dev/null
    [ -n "$LOOP_FILE" ] && rm -f "$LOOP_FILE"
    [ -n "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  OK: $*"; }

if [ "$(id -u)" -ne 0 ]; then
    die "must run as root (sudo)"
fi

command -v systemd-cryptenroll >/dev/null 2>&1 || die "systemd-cryptenroll not found"
command -v pkcs11-tool >/dev/null 2>&1 || die "pkcs11-tool not found"

WORK="$(mktemp -d /tmp/test-pkcs11.XXXXXX)"
chmod 700 "$WORK"

echo "=== Step 1: Create loopback LUKS2 device ==="
LOOP_FILE="$(mktemp /tmp/test-luks.XXXXXX.img)"
dd if=/dev/zero of="$LOOP_FILE" bs=1M count=32 status=none
LOOP_DEV="$(losetup --find --show "$LOOP_FILE")"
ok "loop device: $LOOP_DEV"

PASSPHRASE="test"
printf '%s' "$PASSPHRASE" | cryptsetup luksFormat --type luks2 --batch-mode "$LOOP_DEV" --key-file=-
ok "LUKS2 formatted with passphrase in slot 0"

echo ""
echo "=== Step 2: Enroll smartcard via systemd-cryptenroll ==="

# Find the encryption key URI (slot 0 on OpenPGP cards)
# systemd-cryptenroll refuses "auto" when multiple public keys exist
PKCS11_URI="$(pkcs11-tool --list-slots 2>/dev/null \
    | awk '/uri.*User PIN\)$/{sub(/.*uri *: */,""); print; exit}')"
if [ -z "$PKCS11_URI" ]; then
    # fallback: first uri line
    PKCS11_URI="$(pkcs11-tool --list-slots 2>/dev/null \
        | awk '/uri *:/{sub(/.*uri *: */,""); print; exit}')"
fi
[ -n "$PKCS11_URI" ] || die "cannot determine PKCS#11 token URI"
ok "using token URI: $PKCS11_URI"

echo ">>> You will be prompted for the LUKS passphrase (enter: $PASSPHRASE) <<<"
echo ">>> Then for your smartcard PIN <<<"
systemd-cryptenroll --pkcs11-token-uri="$PKCS11_URI" "$LOOP_DEV"
ok "systemd-cryptenroll completed"

# Show what was created
echo ""
echo "--- LUKS2 token dump ---"
cryptsetup token export --token-id 0 "$LOOP_DEV" 2>/dev/null | head -c 200
echo ""
echo "---"

echo ""
echo "=== Step 3: Test our extract→decrypt→unlock chain ==="

# 3a. Export token (same as boot script does)
TOKEN_JSON="$(cryptsetup token export --token-id 0 "$LOOP_DEV")"
ok "exported token JSON (${#TOKEN_JSON} chars)"

# 3b. Extract base64 blob (using same json_value logic as boot script)
json_value() {
    _jv_json="$1"; _jv_key="$2"
    _jv_flat="$(printf '%s' "$_jv_json" | tr -d '\n')"
    _jv_after="${_jv_flat#*\"${_jv_key}\":\"}"
    [ "$_jv_after" != "$_jv_flat" ] || return 1
    _jv_val="${_jv_after%%\"*}"
    printf '%s' "$_jv_val"
}

TOKEN_TYPE="$(json_value "$TOKEN_JSON" "type")"
ok "token type: $TOKEN_TYPE"
[ "$TOKEN_TYPE" = "systemd-pkcs11" ] || die "unexpected token type: $TOKEN_TYPE"

EXTRACTED_B64="$(json_value "$TOKEN_JSON" "pkcs11-key")"
ok "extracted b64 blob (${#EXTRACTED_B64} chars)"

# 3c. Base64 decode
printf '%s\n' "$EXTRACTED_B64" | base64 -d > "$WORK/encrypted.bin"
ENC_SIZE="$(wc -c < "$WORK/encrypted.bin")"
ok "decoded blob: $ENC_SIZE bytes"

# 3d. Decrypt on smartcard (this is what the boot script does)
echo ""
echo ">>> pkcs11-tool will prompt for your smartcard PIN <<<"
pkcs11-tool --decrypt \
    --mechanism RSA-PKCS \
    --login \
    --input-file "$WORK/encrypted.bin" \
    --output-file "$WORK/decrypted.key"
DEC_SIZE="$(wc -c < "$WORK/decrypted.key")"
ok "decrypted key: $DEC_SIZE bytes"

echo ""
echo "--- Decrypted key hex (first 64 bytes) ---"
xxd -l 64 "$WORK/decrypted.key"
echo "---"

# 3e. Base64-encode the decrypted key (systemd-cryptenroll stores base64 as LUKS passphrase)
base64 -w0 < "$WORK/decrypted.key" > "$WORK/decrypted.b64"
B64_SIZE="$(wc -c < "$WORK/decrypted.b64")"
ok "base64-encoded key: $B64_SIZE bytes"

# 3f. Unlock LUKS with base64-encoded key
echo ""
if cryptsetup luksOpen --test-passphrase --key-file "$WORK/decrypted.b64" "$LOOP_DEV"; then
    ok "LUKS unlocked with card-decrypted key (via base64)"
else
    echo ""
    echo "  FAILED to unlock LUKS with base64-encoded decrypted key."
    echo "  Raw decrypted key size: $DEC_SIZE bytes"
    echo "  Base64-encoded key size: $B64_SIZE bytes"
    echo "  Full hex dump of raw decrypted key:"
    xxd "$WORK/decrypted.key"
    die "LUKS unlock failed — key mismatch"
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo "The full chain works: systemd-cryptenroll → token extract → card decrypt → LUKS unlock"
