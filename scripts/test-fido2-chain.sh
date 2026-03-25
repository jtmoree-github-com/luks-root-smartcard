#!/bin/sh
# Test the full FIDO2 enroll→token→unlock chain
# using a virtual (loopback) LUKS2 device + a real FIDO2 authenticator.
#
# Uses systemd-cryptenroll to add the token (same as real enrollment), then
# exercises the same cryptsetup token unlock path used by initramfs.
#
# Usage:  sudo ./scripts/test-fido2-chain.sh
# Cleanup is automatic on exit.

set -eu

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MAPPER_NAME="test-fido2-$$"

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
command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup not found"

find_fido2_plugin_dir() {
    for _dir in /usr/lib/*/cryptsetup /usr/lib64/cryptsetup; do
        [ -f "$_dir/libcryptsetup-token-systemd-fido2.so" ] || continue
        echo "$_dir"
        return 0
    done
    return 1
}

find_fido2_token_id() {
    _dev="$1"
    _i=0
    while [ "$_i" -lt 32 ]; do
        _json="$(cryptsetup token export --token-id "$_i" "$_dev" 2>/dev/null || true)"
        if [ -n "$_json" ] && printf '%s' "$_json" | grep -q '"type":"systemd-fido2"'; then
            echo "$_i"
            return 0
        fi
        _i=$(( _i + 1 ))
    done
    return 1
}

WORK="$(mktemp -d /tmp/test-fido2.XXXXXX)"
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
echo "=== Step 2: Enroll FIDO2 token via systemd-cryptenroll ==="
echo ">>> You will be prompted for the LUKS passphrase (enter: $PASSPHRASE) <<<"
echo ">>> Then touch your FIDO2 key and enter token PIN if required <<<"
systemd-cryptenroll --fido2-device=auto "$LOOP_DEV"
ok "systemd-cryptenroll completed"

echo ""
echo "=== Step 3: Verify LUKS2 systemd-fido2 token ==="
TOKEN_ID="$(find_fido2_token_id "$LOOP_DEV" || true)"
[ -n "$TOKEN_ID" ] || die "no systemd-fido2 token found in LUKS2 header"
ok "found systemd-fido2 token id: $TOKEN_ID"

echo ""
echo "--- LUKS2 token dump ---"
cryptsetup token export --token-id "$TOKEN_ID" "$LOOP_DEV" | head -c 240
echo ""
echo "---"

PLUGIN_DIR="$(find_fido2_plugin_dir || true)"
[ -n "$PLUGIN_DIR" ] || die "libcryptsetup-token-systemd-fido2.so not found"
ok "using token plugin directory: $PLUGIN_DIR"

echo ""
echo "=== Step 4: Test token unlock path ==="
echo ">>> Touch your FIDO2 key and enter token PIN if required <<<"
if cryptsetup luksOpen \
    --token-only \
    --token-type systemd-fido2 \
    --token-id "$TOKEN_ID" \
    --external-tokens-path "$PLUGIN_DIR" \
    "$LOOP_DEV" "$MAPPER_NAME"; then
    ok "luksOpen succeeded via systemd-fido2 token"
else
    die "luksOpen failed via systemd-fido2 token"
fi

cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || die "mapper not active after unlock"
ok "mapper active: /dev/mapper/$MAPPER_NAME"

cryptsetup close "$MAPPER_NAME"
ok "mapper closed"

echo ""
echo "=== ALL TESTS PASSED ==="
echo "The full FIDO2 chain works:"
echo "  systemd-cryptenroll --fido2-device=auto → token stored → cryptsetup token unlock"
