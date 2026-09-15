#!/bin/sh
# Test gpg-cryptmount end-to-end with a loopback LUKS2 device + smartcard.
#
# Flow:
# 1) Create loopback LUKS2 device
# 2) Create ext4 filesystem inside the unlocked mapping
# 3) Enroll gpg-token using gpg-cryptenroll
# 4) Run gpg-cryptmount and verify:
#    - default mapper name is luks-<uuid>
#    - mountpoint is active
#    - second run is idempotent

set -eu

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MOUNT_POINT=""
RECIPIENT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --recipient) RECIPIENT="${2:-}"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--recipient <gpg-id>]"
      echo "  If --recipient is omitted, gpg-cryptenroll auto-detects from the smartcard."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  OK: $*"; }

if [ "$(id -u)" -eq 0 ]; then
  die "run as normal user, not root (sudo is used internally)"
fi

command -v gpg >/dev/null 2>&1 || die "gpg not found"
command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup not found"
command -v mount >/dev/null 2>&1 || die "mount not found"
command -v findmnt >/dev/null 2>&1 || die "findmnt not found"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/gpg-cryptenroll" ]; then
  GPG_CRYPTENROLL="$SCRIPT_DIR/gpg-cryptenroll"
elif command -v gpg-cryptenroll >/dev/null 2>&1; then
  GPG_CRYPTENROLL="gpg-cryptenroll"
else
  die "gpg-cryptenroll not found (not in $SCRIPT_DIR nor in PATH)"
fi

if [ -x "$SCRIPT_DIR/gpg-cryptmount" ]; then
  GPG_CRYPTMOUNT="$SCRIPT_DIR/gpg-cryptmount"
elif command -v gpg-cryptmount >/dev/null 2>&1; then
  GPG_CRYPTMOUNT="gpg-cryptmount"
else
  die "gpg-cryptmount not found (not in $SCRIPT_DIR nor in PATH)"
fi

cleanup() {
  set +e
  if [ -n "$MOUNT_POINT" ] && findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
    sudo umount "$MOUNT_POINT" 2>/dev/null
  fi

  if [ -n "$LOOP_DEV" ]; then
    _uuid="$(sudo blkid -s UUID -o value "$LOOP_DEV" 2>/dev/null || true)"
    if [ -n "$_uuid" ]; then
      _mapper="luks-$(printf '%s' "$_uuid" | tr '[:upper:]' '[:lower:]')"
      sudo cryptsetup close "$_mapper" 2>/dev/null || true
    fi
  fi

  [ -n "$LOOP_DEV" ] && sudo losetup -d "$LOOP_DEV" 2>/dev/null
  [ -n "$LOOP_FILE" ] && rm -f "$LOOP_FILE"
  [ -n "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT

WORK="$(mktemp -d /tmp/test-gpg-mount.XXXXXX)"
chmod 700 "$WORK"
MOUNT_POINT="$WORK/mnt"

# Step 1: loopback luks device
echo "=== Step 1: Create loopback LUKS2 device ==="
LOOP_FILE="$(mktemp /tmp/test-luks.XXXXXX.img)"
dd if=/dev/zero of="$LOOP_FILE" bs=1M count=64 status=none
LOOP_DEV="$(sudo losetup --find --show "$LOOP_FILE")"
ok "loop device: $LOOP_DEV"

PASSPHRASE="test"
printf '%s' "$PASSPHRASE" | sudo cryptsetup luksFormat --type luks2 --batch-mode "$LOOP_DEV" --key-file=-
ok "LUKS2 formatted"

# Step 2: create filesystem in mapping (temporary passphrase open)
echo ""
echo "=== Step 2: Create ext4 filesystem in encrypted mapping ==="
TMP_MAPPER="tmp-fs-$$"
printf '%s' "$PASSPHRASE" | sudo cryptsetup luksOpen "$LOOP_DEV" "$TMP_MAPPER" --key-file=-
sudo mkfs.ext4 -q "/dev/mapper/$TMP_MAPPER"
sudo cryptsetup close "$TMP_MAPPER"
ok "ext4 filesystem created"

# Step 3: enroll gpg-token
echo ""
echo "=== Step 3: Enroll gpg-token with gpg-cryptenroll ==="
ENROLL_ARGS="token:auto $LOOP_DEV"
[ -n "$RECIPIENT" ] && ENROLL_ARGS="$ENROLL_ARGS --recipient $RECIPIENT"

echo ">>> You will be prompted for LUKS passphrase (enter: $PASSPHRASE) <<<"
echo ">>> Then for smartcard PIN (if required) <<<"
# shellcheck disable=SC2086
sudo "$GPG_CRYPTENROLL" $ENROLL_ARGS
ok "gpg-cryptenroll completed"

# Step 4: run gpg-cryptmount with explicit mountpoint
echo ""
echo "=== Step 4: gpg-cryptmount open + mount ==="
MOUNT_OUT="$(sudo "$GPG_CRYPTMOUNT" "$LOOP_DEV" --mount-point "$MOUNT_POINT")"
[ "$MOUNT_OUT" = "$MOUNT_POINT" ] || die "unexpected mount output: $MOUNT_OUT"
ok "gpg-cryptmount mounted at $MOUNT_POINT"

UUID="$(sudo blkid -s UUID -o value "$LOOP_DEV" | tr '[:upper:]' '[:lower:]')"
[ -n "$UUID" ] || die "could not read UUID"
EXPECTED_MAPPER="luks-$UUID"

sudo cryptsetup status "$EXPECTED_MAPPER" >/dev/null 2>&1 || die "expected mapper $EXPECTED_MAPPER is not active"
ok "default mapper naming follows convention: $EXPECTED_MAPPER"

findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1 || die "mountpoint not active: $MOUNT_POINT"
ok "mountpoint is active"

# Step 5: idempotency
echo ""
echo "=== Step 5: Idempotency check ==="
SECOND_OUT="$(sudo "$GPG_CRYPTMOUNT" "$LOOP_DEV" --mount-point "$MOUNT_POINT")"
[ "$SECOND_OUT" = "$MOUNT_POINT" ] || die "second run should return existing mountpoint"
ok "second run is idempotent"

echo ""
echo "=== ALL TESTS PASSED ==="
echo "gpg-cryptmount open+mount workflow works with mapper convention luks-<uuid>."
