#!/bin/sh
# Test the full GPG file encrypt→decrypt→unlock chain
# using a virtual (loopback) LUKS2 device + the real smartcard.
#
# Uses gpg-cryptenroll to generate a random key, encrypt it to a .gpg file,
# and enroll it into a LUKS keyslot.  Then exercises the same
# gpg --decrypt → cryptsetup luksOpen path that the boot script uses.
#
# This tests the "GPG key file in crypttab field 3" workflow, as opposed to
# the "root-gpg LUKS2 token" workflow tested by test-gpg-token-chain.sh.
#
# Run as your normal user — sudo is used internally where root is needed.
# Usage:  ./scripts/test-gpg-file-chain.sh [--recipient <gpg-id>]
# Cleanup is automatic on exit.

set -eu

# ── Stop pcscd so scdaemon can access the card directly ──────────────────────
# pcscd holds an exclusive lock on the smartcard reader; killing it before
# any GPG card operation is required for scdaemon to work.
if sudo systemctl stop pcscd pcscd.socket 2>/dev/null; then
  echo "Stopped pcscd (will restart on exit)"
fi
_pcscd_stopped=1

_cleanup_pcscd() {
  [ "${_pcscd_stopped:-0}" -eq 1 ] && sudo systemctl start pcscd 2>/dev/null || true
}

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MAPPER_NAME="test-gpg-file-$$"
RECIPIENT=""

# ── Parse arguments ──────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --recipient) RECIPIENT="${2:-}"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--recipient <gpg-id>]"
      echo "  If --recipient is omitted, gpg-cryptenroll auto-detects from the smartcard."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
cleanup() {
  set +e
  [ -n "$MAPPER_NAME" ] && sudo cryptsetup close "$MAPPER_NAME" 2>/dev/null
  [ -n "$LOOP_DEV" ]    && sudo losetup -d "$LOOP_DEV" 2>/dev/null
  [ -n "$LOOP_FILE" ]   && rm -f "$LOOP_FILE"
  [ -n "$WORK" ]        && rm -rf "$WORK"
  _cleanup_pcscd
}
trap cleanup EXIT

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  OK: $*"; }

if [ "$(id -u)" -eq 0 ]; then
  die "run as your normal user, not root — sudo is used internally where needed"
fi

command -v gpg        >/dev/null 2>&1 || die "gpg not found"
command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup not found"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/gpg-cryptenroll" ]; then
  GPG_CRYPTENROLL="$SCRIPT_DIR/gpg-cryptenroll"
elif command -v gpg-cryptenroll >/dev/null 2>&1; then
  GPG_CRYPTENROLL="gpg-cryptenroll"
else
  die "gpg-cryptenroll not found (not in $SCRIPT_DIR nor in PATH)"
fi

WORK="$(mktemp -d /tmp/test-gpg-file.XXXXXX)"
chmod 700 "$WORK"
KEY_FILE="$WORK/root.key.gpg"

# ── Step 1: Create loopback LUKS2 device ─────────────────────────────────────
echo "=== Step 1: Create loopback LUKS2 device ==="
LOOP_FILE="$(mktemp /tmp/test-luks.XXXXXX.img)"
dd if=/dev/zero of="$LOOP_FILE" bs=1M count=32 status=none
LOOP_DEV="$(sudo losetup --find --show "$LOOP_FILE")"
ok "loop device: $LOOP_DEV"

PASSPHRASE="test"
printf '%s' "$PASSPHRASE" | sudo cryptsetup luksFormat --type luks2 --batch-mode "$LOOP_DEV" --key-file=-
ok "LUKS2 formatted with passphrase in slot 0"

# ── Step 2: Enroll via gpg-cryptenroll (file output, no token) ───────────────
# ── Reset scdaemon before any GPG operation ──────────────────────────────────
echo ""
echo "=== Step 1b: Reset gpg-agent / scdaemon ==="
gpgconf --kill gpg-agent scdaemon 2>/dev/null || true
sleep 1
gpg --card-status >/dev/null || die "smartcard not accessible after gpg-agent reset — is the card inserted?"
ok "smartcard accessible"

echo ""
echo "=== Step 2: Enroll GPG key file via gpg-cryptenroll ==="

ENROLL_ARGS="file:$KEY_FILE $LOOP_DEV"
[ -n "$RECIPIENT" ] && ENROLL_ARGS="$ENROLL_ARGS --recipient $RECIPIENT"

echo ">>> You will be prompted for the LUKS passphrase (enter: $PASSPHRASE) <<<"
echo ">>> Then for your smartcard PIN (if the card requires it) <<<"
# shellcheck disable=SC2086
sudo "$GPG_CRYPTENROLL" $ENROLL_ARGS
ok "gpg-cryptenroll completed"

# gpg-cryptenroll (running as root) creates the file root:root 600.
# Make it readable for user-run gpg in steps 3 and 4.
sudo chmod 644 "$KEY_FILE"
ok "encrypted key file: $KEY_FILE"

ENC_SIZE="$(wc -c < "$KEY_FILE")"
ok "encrypted key file size: $ENC_SIZE bytes"

# ── Step 3: Verify key file looks like a GPG message ─────────────────────────
echo ""
echo "=== Step 3: Verify key file is a GPG binary message ==="

gpg --list-packets "$KEY_FILE" >/dev/null 2>&1 || die "key file is not a valid GPG message"
ok "key file parses as a valid GPG message"

echo ""
echo "--- GPG packet info ---"
gpg --list-packets "$KEY_FILE" 2>&1 | head -20
echo "---"

# ── Step 4: Decrypt GPG file → plaintext key ─────────────────────────────────
echo ""
echo "=== Step 4: Decrypt GPG key file ==="

echo ">>> gpg will prompt for your smartcard PIN <<<"
gpg --batch --yes --no-options --trust-model=always \
  --decrypt \
  --output "$WORK/decrypted.key" \
  -- "$KEY_FILE"

DEC_SIZE="$(wc -c < "$WORK/decrypted.key")"
[ "$DEC_SIZE" -gt 0 ] || die "decrypted key is empty"
ok "decrypted plaintext key: $DEC_SIZE bytes"

echo ""
echo "--- Decrypted key (first 64 bytes hex) ---"
xxd -l 64 "$WORK/decrypted.key"
echo "---"

# ── Step 5: Unlock LUKS with decrypted key ───────────────────────────────────
echo ""
echo "=== Step 5: Unlock LUKS with decrypted key ==="

if sudo cryptsetup luksOpen --test-passphrase --key-file "$WORK/decrypted.key" "$LOOP_DEV"; then
  ok "LUKS unlocked with GPG-decrypted key (--test-passphrase)"
else
  echo ""
  echo "  FAILED to unlock LUKS with decrypted key."
  echo "  Decrypted key size: $DEC_SIZE bytes"
  echo "  Full hex dump:"
  xxd "$WORK/decrypted.key"
  die "LUKS unlock failed — key mismatch"
fi

# Also verify with real luksOpen (mapped device)
sudo cryptsetup luksOpen --key-file "$WORK/decrypted.key" "$LOOP_DEV" "$MAPPER_NAME"
ok "luksOpen succeeded — mapper: /dev/mapper/$MAPPER_NAME"

sudo cryptsetup status "$MAPPER_NAME"
sudo cryptsetup close "$MAPPER_NAME"
ok "mapper closed"

echo ""
echo "=== ALL TESTS PASSED ==="
echo "The full GPG file chain works:"
echo "  gpg-cryptenroll file:root.key.gpg <luks-device> → gpg --decrypt → LUKS unlock"
