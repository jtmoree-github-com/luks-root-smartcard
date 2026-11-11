#!/usr/bin/env bash
set -euo pipefail

KVER="${1:-$(uname -r)}"
KEY="/root/secureboot-keys/MOK.key"
CERT="/root/secureboot-keys/MOK.crt"
CERT_DER="/root/secureboot-keys/MOK.cer"
MOK_SUBJECT="/CN=UKI MOK/"
MOK_DAYS="36500"
BOOT_LABEL_PREFIX="UKI"
BOOT_LABEL="${BOOT_LABEL_PREFIX} ${KVER}"
EFI_DISK_OVERRIDE="${EFI_DISK_OVERRIDE:-}"
EFI_PART_OVERRIDE="${EFI_PART_OVERRIDE:-}"
FILE_PREFIX="$(printf '%s' "$BOOT_LABEL_PREFIX" | tr '[:space:]' '-' | tr -cd '[:alnum:]_.-')"
FILE_PREFIX="${FILE_PREFIX:-uki}"
IMAGE_BASENAME="${FILE_PREFIX}-${KVER}"

ensure_mok_files() {
  # Ensure signing material exists before ukify/sbsign steps.
  local key_dir
  key_dir="$(dirname "$KEY")"
  mkdir -p "$key_dir"
  chmod 0700 "$key_dir"

  if [ ! -f "$KEY" ] && [ ! -f "$CERT" ] && [ ! -f "$CERT_DER" ]; then
    echo "MOK files not found; generating new signing keypair at ${key_dir}"
    openssl req -new -x509 -newkey rsa:4096 -sha256 -nodes \
      -subj "$MOK_SUBJECT" -days "$MOK_DAYS" \
      -keyout "$KEY" -out "$CERT"
  elif [ ! -f "$KEY" ] && { [ -f "$CERT" ] || [ -f "$CERT_DER" ]; }; then
    echo "MOK private key not found; generating new keypair and replacing certificate files in ${key_dir}"
    openssl req -new -x509 -newkey rsa:4096 -sha256 -nodes \
      -subj "$MOK_SUBJECT" -days "$MOK_DAYS" \
      -keyout "$KEY" -out "$CERT"
  elif [ -f "$KEY" ] && [ ! -f "$CERT" ] && [ -f "$CERT_DER" ]; then
    echo "MOK PEM certificate not found; converting from ${CERT_DER}"
    openssl x509 -inform DER -in "$CERT_DER" -out "$CERT"
  elif [ -f "$KEY" ] && [ ! -f "$CERT" ]; then
    echo "MOK certificate not found; generating from existing private key"
    openssl req -new -x509 -sha256 \
      -subj "$MOK_SUBJECT" -days "$MOK_DAYS" \
      -key "$KEY" -out "$CERT"
  fi

  if [ ! -f "$CERT_DER" ] || [ "$CERT" -nt "$CERT_DER" ]; then
    echo "Generating DER certificate ${CERT_DER}"
    openssl x509 -in "$CERT" -outform DER -out "$CERT_DER"
  fi

  chmod 0600 "$KEY"
  chmod 0644 "$CERT" "$CERT_DER"

  if ! openssl x509 -noout -modulus -in "$CERT" | cmp -s - <(openssl rsa -noout -modulus -in "$KEY" 2>/dev/null); then
    echo "ERROR: MOK certificate and private key do not match (${CERT} vs ${KEY})" >&2
    exit 1
  fi
}

ensure_mok_files

for p in /boot/efi /efi; do
  if findmnt -rn -T "$p" >/dev/null 2>&1 && [ -d "$p/EFI" ]; then
    ESP="$p"
    break
  fi
done
: "${ESP:?Could not find ESP mount (/efi or /boot/efi)}"

ROOT_UUID="$(findmnt -no UUID /)"
if [ -f /etc/kernel/cmdline ]; then
  CMDLINE="$(tr '\n' ' ' < /etc/kernel/cmdline | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
else
  CMDLINE="root=UUID=${ROOT_UUID} ro quiet splash"
fi

OUTDIR="${ESP}/EFI/UKI"
UNSIGNED="${OUTDIR}/${IMAGE_BASENAME}.efi"
SIGNED="${OUTDIR}/${IMAGE_BASENAME}-signed.efi"
mkdir -p "$OUTDIR"
install -m 0644 "$CERT_DER" "${OUTDIR}/MOK.cer"

ukify build \
  --linux "/boot/vmlinuz-${KVER}" \
  --initrd "/boot/initrd.img-${KVER}" \
  --cmdline "${CMDLINE}" \
  --os-release /etc/os-release \
  --output "${UNSIGNED}"

sbsign --key "${KEY}" --cert "${CERT}" --output "${SIGNED}" "${UNSIGNED}"
sbverify --cert "${CERT}" "${SIGNED}" >/dev/null

ESP_SRC="$(findmnt -nr -o SOURCE -T "$ESP")"
ESP_DEV="$(realpath "$ESP_SRC")"
DISK=""
PART=""

if [ -n "$EFI_DISK_OVERRIDE" ] || [ -n "$EFI_PART_OVERRIDE" ]; then
  : "${EFI_DISK_OVERRIDE:?Set EFI_DISK_OVERRIDE when using override mode}"
  : "${EFI_PART_OVERRIDE:?Set EFI_PART_OVERRIDE when using override mode}"
  DISK="$EFI_DISK_OVERRIDE"
  PART="$EFI_PART_OVERRIDE"
elif [[ "$ESP_DEV" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
  DISK="${BASH_REMATCH[1]}"
  PART="${BASH_REMATCH[2]}"
elif [[ "$ESP_DEV" =~ ^(/dev/mmcblk[0-9]+)p([0-9]+)$ ]]; then
  DISK="${BASH_REMATCH[1]}"
  PART="${BASH_REMATCH[2]}"
elif [[ "$ESP_DEV" =~ ^(/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+))([0-9]+)$ ]]; then
  DISK="${BASH_REMATCH[1]}"
  PART="${BASH_REMATCH[3]}"
else
  DISK="/dev/$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null || true)"
  PART="$(cat "/sys/class/block/$(basename "$ESP_DEV")/partition" 2>/dev/null || true)"
fi

: "${DISK:?Could not determine ESP parent disk from ${ESP_DEV}}"
: "${PART:?Could not determine ESP partition number from ${ESP_DEV}}"
EFI_PATH="\\EFI\\UKI\\${IMAGE_BASENAME}-signed.efi"

EFI_PATH_LOWER="$(printf '%s' "$EFI_PATH" | tr '[:upper:]' '[:lower:]')"
# Safety: only remove entries that are exact duplicates of this kernel's UKI path
# or entries with the exact target label. Do not remove other working boot options.
mapfile -t BOOTNUMS < <(
  efibootmgr -v 2>/dev/null | awk -v lbl="$BOOT_LABEL" -v efi_path_lower="$EFI_PATH_LOWER" '
    /^Boot[0-9A-Fa-f]{4}\*/ {
      entry = $0
      entry_lower = tolower(entry)
      if (index(entry, lbl) > 0 || index(entry_lower, efi_path_lower) > 0) {
        print substr($1, 5, 4)
      }
    }'
)
for bootnum in "${BOOTNUMS[@]}"; do
  [[ "$bootnum" =~ ^[0-9A-Fa-f]{4}$ ]] || continue
  efibootmgr -b "$bootnum" -B >/dev/null 2>&1
done

efibootmgr -c -d "$DISK" -p "$PART" -L "$BOOT_LABEL" -l "$EFI_PATH" >/dev/null
NEW_BOOTNUM="$(
  efibootmgr -v 2>/dev/null | awk -v lbl="$BOOT_LABEL" -v efi_path_lower="$EFI_PATH_LOWER" '
    /^Boot[0-9A-Fa-f]{4}\*/ {
      entry = $0
      entry_lower = tolower(entry)
      if (index(entry, lbl) > 0 && index(entry_lower, efi_path_lower) > 0) {
        print substr($1, 5, 4)
        exit
      }
    }'
)"
if [ -n "${NEW_BOOTNUM:-}" ]; then
  efibootmgr -b "$NEW_BOOTNUM" -L "$BOOT_LABEL" >/dev/null
fi

echo "Built/signed UKI: $SIGNED"
echo "Copied cert: ${OUTDIR}/MOK.cer"
echo "Using ESP mount: $ESP"
echo "Using ESP source: $ESP_SRC -> $ESP_DEV"
echo "Using efibootmgr target: disk=$DISK part=$PART"
echo "Using boot label: $BOOT_LABEL"
if [ -n "${NEW_BOOTNUM:-}" ]; then
  echo "Created boot entry: Boot${NEW_BOOTNUM}"
else
  echo "Created boot entry: (unable to resolve boot number from label/path; verify with: efibootmgr -v)"
fi
echo "Boot entry now points to: $EFI_PATH"
