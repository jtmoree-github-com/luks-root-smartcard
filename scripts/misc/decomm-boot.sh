#!/usr/bin/env bash
set -euo pipefail

msg() { echo "decomm-boot: $*" >&2; }
die() { echo "decomm-boot: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }
usage() {
  cat <<'EOF'
Usage: decomm-boot.sh [--copy-only]

Options:
  --copy-only   Copy and validate /boot content, but do not edit /etc/fstab.
  --help        Show this help.
EOF
}

COPY_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --copy-only) COPY_ONLY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "must be run as root"
for cmd in findmnt mount umount rsync mkdir; do
  require_cmd "$cmd"
done
if [ "$COPY_ONLY" -eq 0 ]; then
  for cmd in awk mktemp cp date rm; do
    require_cmd "$cmd"
  done
fi

declare -a NESTED_TARGETS=()

BOOT_TARGET="$(findmnt -nr -o TARGET -T /boot || true)"
BOOT_SOURCE="$(findmnt -nr -o SOURCE -T /boot || true)"
BOOT_FSTYPE="$(findmnt -nr -o FSTYPE -T /boot || true)"

[ -n "$BOOT_TARGET" ] || die "cannot determine mount target for /boot"
[ -n "$BOOT_SOURCE" ] || die "cannot determine current /boot source"
[ -n "$BOOT_FSTYPE" ] || die "cannot determine current /boot filesystem type"

if [ "$BOOT_TARGET" != "/boot" ]; then
  die "/boot is not a separate mount; no changes made"
fi

msg "detected separate /boot: source=$BOOT_SOURCE fstype=$BOOT_FSTYPE"

while IFS= read -r nested_target; do
  [ -n "$nested_target" ] || continue
  [ "$nested_target" = "/boot" ] && continue
  NESTED_TARGETS+=("$nested_target")
done < <(findmnt -R -r -n -o TARGET -T /boot || true)

if [ "${#NESTED_TARGETS[@]}" -gt 0 ]; then
  msg "found nested mounts under /boot; unmounting them first"
  for ((i=${#NESTED_TARGETS[@]}-1; i>=0; i--)); do
    msg "unmounting nested mount ${NESTED_TARGETS[$i]}"
    umount "${NESTED_TARGETS[$i]}"
  done
fi

if [ ! -d /mnt/boot ]; then
  mkdir /mnt/boot
fi
[ -d /mnt/boot ] || die "failed to create /mnt/boot"

msg "unmounting /boot"
umount /boot

msg "mounting $BOOT_SOURCE at /mnt/boot"
mount -t "$BOOT_FSTYPE" "$BOOT_SOURCE" /mnt/boot

msg "copying boot files from /mnt/boot to /boot"
rsync -aHAX --numeric-ids /mnt/boot/ /boot/

msg "validating copied files"
VERIFY_OUTPUT="$(rsync -aHAX --numeric-ids --checksum --dry-run --itemize-changes /mnt/boot/ /boot/)"
if [ -n "$VERIFY_OUTPUT" ]; then
  printf '%s\n' "$VERIFY_OUTPUT" >&2
  die "copy validation failed: /boot does not match /mnt/boot"
fi

if [ "$COPY_ONLY" -eq 0 ]; then
  msg "updating /etc/fstab (commenting active /boot entry)"
  FSTAB_TMP="$(mktemp)"
  FSTAB_BACKUP="/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  cp -a /etc/fstab "$FSTAB_BACKUP"
  msg "done. backup created: $FSTAB_BACKUP"

  if ! awk '
    BEGIN { changed = 0 }
    /^[[:space:]]*#/ { print; next }
    NF < 2 { print; next }
    $2 == "/boot" {
      print "# " $0
      changed = 1
      next
    }
    { print }
    END { exit(changed ? 0 : 3) }
  ' /etc/fstab >"$FSTAB_TMP"; then
    rc=$?
    rm -f "$FSTAB_TMP"
    if [ "$rc" -eq 3 ]; then
      die "did not find an active /boot entry in /etc/fstab"
    fi
    die "failed to rewrite /etc/fstab"
  fi

  cp -f "$FSTAB_TMP" /etc/fstab
  rm -f "$FSTAB_TMP"
else
  msg "--copy-only set: skipping /etc/fstab changes"
fi

msg "unmounting /mnt/boot"
umount /mnt/boot

msg "remounting mounts from /etc/fstab with mount -a"
mount -a

msg "reboot and confirm expected boot behavior"