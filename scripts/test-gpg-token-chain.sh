#!/bin/sh
# Test the full GPG token encrypt→store→extract→decrypt→unlock chain
# using a virtual (loopback) LUKS2 device + the real smartcard.
#
# Uses gpg-cryptenroll to generate a key, enroll into a LUKS keyslot,
# and store the encrypted blob as a LUKS2 gpg-token token.
# Then exercises the same extract→decrypt→unlock path the boot script uses.
#
# Run as your normal user — sudo is used internally where root is needed.
# Usage:  ./scripts/test-gpg-token-chain.sh [--recipient <gpg-id>]
# Cleanup is automatic on exit.

set -eu

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MAPPER_NAME="test-gpg-token-$$"
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
}
trap cleanup EXIT

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  OK: $*"; }

json_value() {
  _jv_json="$1"; _jv_key="$2"
  _jv_flat="$(printf '%s' "$_jv_json" | tr -d '\n')"
  _jv_after="${_jv_flat#*\"${_jv_key}\":\"}"
  [ "$_jv_after" != "$_jv_flat" ] || return 1
  _jv_val="${_jv_after%%\"*}"
  printf '%s' "$_jv_val"
}

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

if [ -x "$SCRIPT_DIR/gpg-cryptopen" ]; then
  GPG_CRYPTOPEN="$SCRIPT_DIR/gpg-cryptopen"
elif command -v gpg-cryptopen >/dev/null 2>&1; then
  GPG_CRYPTOPEN="gpg-cryptopen"
else
  die "gpg-cryptopen not found (not in $SCRIPT_DIR nor in PATH)"
fi

WORK="$(mktemp -d /tmp/test-gpg-token.XXXXXX)"
chmod 700 "$WORK"

# ── Step 1: Create loopback LUKS2 device ─────────────────────────────────────
echo "=== Step 1: Create loopback LUKS2 device ==="
LOOP_FILE="$(mktemp /tmp/test-luks.XXXXXX.img)"
dd if=/dev/zero of="$LOOP_FILE" bs=1M count=32 status=none
LOOP_DEV="$(sudo losetup --find --show "$LOOP_FILE")"
ok "loop device: $LOOP_DEV"

PASSPHRASE="test"
printf '%s' "$PASSPHRASE" | sudo cryptsetup luksFormat --type luks2 --batch-mode "$LOOP_DEV" --key-file=-
ok "LUKS2 formatted with passphrase in slot 0"

# ── Step 2: Enroll via gpg-cryptenroll ───────────────────────────────────────
echo ""
echo "=== Step 2: Enroll GPG key + LUKS2 token via gpg-cryptenroll ==="

ENROLL_ARGS="token:auto $LOOP_DEV"
[ -n "$RECIPIENT" ] && ENROLL_ARGS="$ENROLL_ARGS --recipient $RECIPIENT"

echo ">>> You will be prompted for the LUKS passphrase (enter: $PASSPHRASE) <<<"
echo ">>> Then for your smartcard PIN (if the card requires it) <<<"
# shellcheck disable=SC2086
sudo "$GPG_CRYPTENROLL" $ENROLL_ARGS
ok "gpg-cryptenroll completed"

# ── Step 3: Verify token is present ─────────────────────────────────────────
echo ""
echo "=== Step 3: Verify LUKS2 gpg-token token ==="

# Find the token (scan slots 0-31, same as boot script)
TOKEN_ID=""
TOKEN_JSON=""
_i=0
while [ "$_i" -lt 32 ]; do
  _json="$(sudo cryptsetup token export --token-id "$_i" "$LOOP_DEV" 2>/dev/null || true)"
  if [ -n "$_json" ]; then
    _t="$(json_value "$_json" "type" || true)"
    if [ "$_t" = "gpg-token" ]; then
      TOKEN_ID="$_i"
      TOKEN_JSON="$_json"
      break
    fi
  fi
  _i=$(( _i + 1 ))
done

[ -n "$TOKEN_ID" ] || die "no gpg-token token found in LUKS2 header"
ok "found token id $TOKEN_ID"

TOKEN_TYPE="$(json_value "$TOKEN_JSON" "type")"
ok "token type: $TOKEN_TYPE"

TOKEN_KEYSLOT="$(printf '%s' "$TOKEN_JSON" | tr -d '\n' | sed -n 's/.*"keyslots"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*\].*/\1/p')"
[ -n "$TOKEN_KEYSLOT" ] || die "keyslots field does not include an enrolled slot in gpg-token token JSON"
ok "token metadata keyslots[0]: $TOKEN_KEYSLOT"

echo ""
echo "--- LUKS2 token dump (first 200 chars) ---"
printf '%s\n' "$TOKEN_JSON" | head -c 200
echo ""
echo "---"

# ── Step 4: Extract + decrypt + unlock (same chain as boot script) ───────────
echo ""
echo "=== Step 4: Test extract → decrypt → unlock chain ==="

# 4a. Extract base64-encoded GPG blob from token
GPG_KEY_B64="$(json_value "$TOKEN_JSON" "gpg-key")"
[ -n "$GPG_KEY_B64" ] || die "gpg-key field is empty in token JSON"
ok "extracted gpg-key blob (${#GPG_KEY_B64} base64 chars)"

# 4b. Decode base64 → GPG-encrypted binary
printf '%s\n' "$GPG_KEY_B64" | base64 -d > "$WORK/encrypted.gpg"
ENC_SIZE="$(wc -c < "$WORK/encrypted.gpg")"
ok "decoded GPG blob: $ENC_SIZE bytes"

# 4c. Decrypt with GPG (smartcard PIN prompt)
echo ""
echo ">>> gpg will prompt for your smartcard PIN <<<"
gpg --batch --yes --no-options --trust-model=always \
  --decrypt \
  --output "$WORK/decrypted.key" \
  -- "$WORK/encrypted.gpg"
DEC_SIZE="$(wc -c < "$WORK/decrypted.key")"
ok "decrypted plaintext key: $DEC_SIZE bytes"

echo ""
echo "--- Decrypted key (first 64 bytes hex) ---"
xxd -l 64 "$WORK/decrypted.key"
echo "---"

# 4d. Unlock LUKS with decrypted plaintext key
echo ""
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

# 4e. Also verify it works with real luksOpen (mapped device)
sudo cryptsetup luksOpen --key-file "$WORK/decrypted.key" "$LOOP_DEV" "$MAPPER_NAME"
ok "luksOpen succeeded — mapper: /dev/mapper/$MAPPER_NAME"

sudo cryptsetup status "$MAPPER_NAME"
sudo cryptsetup close "$MAPPER_NAME"
ok "mapper closed"

# ── Step 5: Validate gpg-cryptopen (token-based flow) ───────────────────────
echo ""
echo "=== Step 5: Validate gpg-cryptopen (token-based unlock) ==="

echo ">>> gpg-cryptopen will prompt for your smartcard PIN <<<"
sudo "$GPG_CRYPTOPEN" "$LOOP_DEV" --name "$MAPPER_NAME"
sudo cryptsetup status "$MAPPER_NAME" | grep 'is active' >/dev/null \
  || die "gpg-cryptopen: /dev/mapper/$MAPPER_NAME not active after open"
ok "gpg-cryptopen opened /dev/mapper/$MAPPER_NAME"

# Idempotency: second call must exit 0 and report already-open.
sudo "$GPG_CRYPTOPEN" "$LOOP_DEV" --name "$MAPPER_NAME" 2>&1 \
  | grep -q 'already open' \
  || die "gpg-cryptopen: expected 'already open' on second call"
ok "gpg-cryptopen is idempotent (already open)"

sudo cryptsetup close "$MAPPER_NAME"
ok "mapper closed"

echo ""
echo "=== ALL TESTS PASSED ==="
echo "The full GPG token chain works:"
echo "  gpg-cryptenroll → token stored → extract blob → gpg decrypt → LUKS unlock"
echo "  gpg-cryptopen (token:auto) → luksOpen"
