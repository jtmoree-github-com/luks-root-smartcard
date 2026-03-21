#!/bin/sh
# Test the full TPM2 enroll→extract→unseal→unlock chain
# using a virtual (loopback) LUKS2 device + local TPM2 device.
#
# Uses systemd-cryptenroll to add a systemd-tpm2 token, then exercises
# the same token parse + blob split + tpm2_load + tpm2_unseal flow that
# initramfs/local-top/00-smartcard-root-tpm2 uses.
#
# Usage: sudo ./scripts/test-tpm2-chain.sh [--pcrs <list>] [--pcr-bank <bank>]
# Example: sudo ./scripts/test-tpm2-chain.sh --pcrs 7 --pcr-bank sha256

set -eu

LOOP_FILE=""
LOOP_DEV=""
WORK=""
MAPPER_NAME="test-tpm2-$$"
PCRS="7"
PCR_BANK="sha256"

cleanup() {
    set +e
    [ -n "$MAPPER_NAME" ] && cryptsetup close "$MAPPER_NAME" 2>/dev/null
    [ -n "$LOOP_DEV" ] && losetup -d "$LOOP_DEV" 2>/dev/null
    [ -n "$LOOP_FILE" ] && rm -f "$LOOP_FILE"
    [ -n "$WORK" ] && rm -rf "$WORK"
    tpm2_flushcontext -t >/dev/null 2>&1 || true
}
trap cleanup EXIT

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  OK: $*"; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pcrs) PCRS="${2:-}"; shift 2 ;;
        --pcr-bank) PCR_BANK="${2:-}"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--pcrs <list>] [--pcr-bank <bank>]"
            echo "Defaults: --pcrs 7 --pcr-bank sha256"
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    die "must run as root (sudo)"
fi

command -v systemd-cryptenroll >/dev/null 2>&1 || die "systemd-cryptenroll not found"
command -v cryptsetup >/dev/null 2>&1 || die "cryptsetup not found"
command -v tpm2_createprimary >/dev/null 2>&1 || die "tpm2-tools not found (tpm2_createprimary missing)"
command -v tpm2_load >/dev/null 2>&1 || die "tpm2-tools not found (tpm2_load missing)"
command -v tpm2_unseal >/dev/null 2>&1 || die "tpm2-tools not found (tpm2_unseal missing)"
command -v tpm2_readpublic >/dev/null 2>&1 || die "tpm2-tools not found (tpm2_readpublic missing)"

if [ -c /dev/tpmrm0 ]; then
    TPM_DEV="/dev/tpmrm0"
elif [ -c /dev/tpm0 ]; then
    TPM_DEV="/dev/tpm0"
else
    die "no TPM2 device found (/dev/tpmrm0 or /dev/tpm0)"
fi
export TPM2TOOLS_TCTI="device:${TPM_DEV}"
ok "using TPM device: ${TPM_DEV}"

json_value() {
    _jv_json="$1"; _jv_key="$2"
    _jv_flat="$(printf '%s' "$_jv_json" | tr -d '\n')"
    _jv_after="${_jv_flat#*\"${_jv_key}\":\"}"
    [ "$_jv_after" != "$_jv_flat" ] || return 1
    _jv_val="${_jv_after%%\"*}"
    printf '%s' "$_jv_val"
}

json_int_value() {
    _jv_json="$1"; _jv_key="$2"
    _jv_flat="$(printf '%s' "$_jv_json" | tr -d '\n')"
    _jv_after="${_jv_flat#*\"${_jv_key}\":}"
    [ "$_jv_after" != "$_jv_flat" ] || return 1
    _jv_after="${_jv_after# }"
    _jv_val="${_jv_after%%[^0-9]*}"
    [ -n "$_jv_val" ] || return 1
    printf '%s' "$_jv_val"
}

json_bool_value() {
    _jv_json="$1"; _jv_key="$2"
    _jv_flat="$(printf '%s' "$_jv_json" | tr -d '\n')"
    _jv_after="${_jv_flat#*\"${_jv_key}\":}"
    [ "$_jv_after" != "$_jv_flat" ] || return 1
    _jv_after="${_jv_after# }"
    case "$_jv_after" in
        true*) printf 'true' ;;
        false*) printf 'false' ;;
        *) return 1 ;;
    esac
}

pcr_mask_to_list() {
    _m="$(printf '%d' "${1:-0}" 2>/dev/null)" || return 1
    _list=""
    _i=0
    while [ "$_m" -gt 0 ]; do
        if [ $(( _m & 1 )) -eq 1 ]; then
            _list="${_list:+$_list,}$_i"
        fi
        _m=$(( _m >> 1 ))
        _i=$(( _i + 1 ))
    done
    printf '%s' "$_list"
}

split_tpm2_blob() {
    _blob="$1"
    _pub_out="$2"
    _priv_out="$3"

    _hex2="$(dd if="$_blob" bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    _b1_dec="$(printf '%d' "0x${_hex2%??}")"
    _b2_dec="$(printf '%d' "0x${_hex2#??}")"
    _pub_sz=$(( _b1_dec * 256 + _b2_dec ))
    _pub_total=$(( _pub_sz + 2 ))

    dd if="$_blob" bs=1 count="$_pub_total" of="$_pub_out" 2>/dev/null
    dd if="$_blob" bs=1 skip="$_pub_total" of="$_priv_out" 2>/dev/null
}

echo "=== Step 1: Create loopback LUKS2 device ==="
WORK="$(mktemp -d /tmp/test-tpm2.XXXXXX)"
chmod 700 "$WORK"

LOOP_FILE="$(mktemp /tmp/test-luks.XXXXXX.img)"
dd if=/dev/zero of="$LOOP_FILE" bs=1M count=32 status=none
LOOP_DEV="$(losetup --find --show "$LOOP_FILE")"
ok "loop device: $LOOP_DEV"

PASSPHRASE="test"
printf '%s' "$PASSPHRASE" | cryptsetup luksFormat --type luks2 --batch-mode "$LOOP_DEV" --key-file=-
ok "LUKS2 formatted with passphrase in slot 0"

echo ""
echo "=== Step 2: Enroll TPM2 via systemd-cryptenroll ==="
echo ">>> You may be prompted for the LUKS passphrase (enter: $PASSPHRASE) <<<"
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs="$PCRS" --tpm2-pcr-bank="$PCR_BANK" "$LOOP_DEV"
ok "systemd-cryptenroll completed"

echo ""
echo "=== Step 3: Locate and export systemd-tpm2 token ==="
TOKEN_ID=""
TOKEN_JSON=""
_i=0
while [ "$_i" -lt 32 ]; do
    _json="$(cryptsetup token export --token-id "$_i" "$LOOP_DEV" 2>/dev/null || true)"
    if [ -n "$_json" ]; then
        _t="$(json_value "$_json" "type" || true)"
        if [ "$_t" = "systemd-tpm2" ]; then
            TOKEN_ID="$_i"
            TOKEN_JSON="$_json"
            break
        fi
    fi
    _i=$(( _i + 1 ))
done

[ -n "$TOKEN_ID" ] || die "no systemd-tpm2 token found in LUKS2 header"
ok "found token id $TOKEN_ID"

echo ""
echo "--- LUKS2 token dump (first 240 chars) ---"
printf '%s\n' "$TOKEN_JSON" | head -c 240
echo ""
echo "---"

echo ""
echo "=== Step 4: Extract TPM2 object + unseal key ==="
BLOB_B64="$(json_value "$TOKEN_JSON" "tpm2-blob" || true)"
[ -n "$BLOB_B64" ] || die "token missing tpm2-blob"

TPM2_PCRS="$(json_int_value "$TOKEN_JSON" "tpm2-pcrs" 2>/dev/null || json_value "$TOKEN_JSON" "tpm2-pcrs" 2>/dev/null || echo "0")"
TPM2_BANK="$(json_value "$TOKEN_JSON" "tpm2-pcr-bank" 2>/dev/null || echo "sha256")"
TPM2_PRIMARY_ALG="$(json_value "$TOKEN_JSON" "tpm2-primary-alg" 2>/dev/null || echo "ecc")"
TPM2_PIN="$(json_bool_value "$TOKEN_JSON" "tpm2-pin" 2>/dev/null || echo "false")"
TPM2_SRK="$(json_int_value "$TOKEN_JSON" "tpm2-srk" 2>/dev/null || echo "")"

ok "token fields: pcrs=$TPM2_PCRS bank=$TPM2_BANK primary=$TPM2_PRIMARY_ALG pin=$TPM2_PIN srk=${TPM2_SRK:-none}"
[ "$TPM2_PIN" = "false" ] || die "token requires tpm2-pin; this test currently supports non-pin tokens only"

printf '%s' "$BLOB_B64" | base64 -d > "$WORK/blob.bin"
split_tpm2_blob "$WORK/blob.bin" "$WORK/pub.bin" "$WORK/priv.bin"
[ -s "$WORK/pub.bin" ] || die "public object split failed"
[ -s "$WORK/priv.bin" ] || die "private object split failed"
ok "split tpm2-blob into TPM2B_PUBLIC and TPM2B_PRIVATE"

PRIMARY_CTX="$WORK/primary.ctx"
if [ -n "$TPM2_SRK" ] && [ "$TPM2_SRK" -gt 0 ] 2>/dev/null; then
    SRK_HEX="$(printf '0x%x' "$TPM2_SRK")"
    if tpm2_readpublic -c "$SRK_HEX" >/dev/null 2>&1; then
        PRIMARY_CTX="$SRK_HEX"
        ok "using persistent SRK: $SRK_HEX"
    fi
fi

if [ "$PRIMARY_CTX" = "$WORK/primary.ctx" ]; then
    case "$TPM2_PRIMARY_ALG" in
        ecc*) PRIMARY_ALG_ARG="ecc256:aes128cfb" ;;
        rsa*) PRIMARY_ALG_ARG="rsa2048:aes128cfb" ;;
        *) PRIMARY_ALG_ARG="ecc256:aes128cfb" ;;
    esac

    tpm2_createprimary -C o -G "$PRIMARY_ALG_ARG" \
        -a 'fixedtpm|fixedparent|sensitivedataorigin|userwithauth|noda|restricted|decrypt' \
        -c "$PRIMARY_CTX" >/dev/null
    tpm2_flushcontext -t >/dev/null 2>&1 || true
    ok "recreated SRK primary context"
fi

tpm2_load -C "$PRIMARY_CTX" -u "$WORK/pub.bin" -r "$WORK/priv.bin" -c "$WORK/sealed.ctx" >/dev/null
tpm2_flushcontext -t >/dev/null 2>&1 || true
ok "loaded sealed TPM2 object"

PCR_LIST="$(pcr_mask_to_list "$TPM2_PCRS" || echo "")"
if [ -n "$PCR_LIST" ]; then
    PCR_AUTH="${TPM2_BANK}:${PCR_LIST}"
    tpm2_unseal -c "$WORK/sealed.ctx" -p "pcr:${PCR_AUTH}" -o "$WORK/unsealed.key" >/dev/null
    ok "unsealed key with PCR policy pcr:${PCR_AUTH}"
else
    tpm2_unseal -c "$WORK/sealed.ctx" -o "$WORK/unsealed.key" >/dev/null
    ok "unsealed key without PCR policy"
fi
tpm2_flushcontext -t >/dev/null 2>&1 || true

KEY_SIZE="$(wc -c < "$WORK/unsealed.key")"
[ "$KEY_SIZE" -gt 0 ] || die "unsealed key is empty"
ok "unsealed key size: $KEY_SIZE bytes"

echo ""
echo "=== Step 5: Unlock LUKS with unsealed key ==="
if cryptsetup luksOpen --test-passphrase --key-file "$WORK/unsealed.key" "$LOOP_DEV"; then
    ok "LUKS unlocked with TPM2-unsealed key (--test-passphrase)"
else
    die "LUKS unlock failed — key mismatch"
fi

cryptsetup luksOpen --key-file "$WORK/unsealed.key" "$LOOP_DEV" "$MAPPER_NAME"
ok "luksOpen succeeded — mapper: /dev/mapper/$MAPPER_NAME"

cryptsetup status "$MAPPER_NAME"
cryptsetup close "$MAPPER_NAME"
ok "mapper closed"

echo ""
echo "=== ALL TESTS PASSED ==="
echo "The full TPM2 chain works:"
echo "  systemd-cryptenroll --tpm2-* -> token export -> blob split -> tpm2_unseal -> LUKS unlock"
