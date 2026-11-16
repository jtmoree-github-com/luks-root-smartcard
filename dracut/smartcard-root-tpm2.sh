#!/bin/sh
# dracut hook: smartcard-root-tpm2
# Runtime smartcard TPM2 token unlock for LUKS2 root device

. /lib/smartcard-common-lib.sh

_load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE" "all"

if [ "${SMARTCARD_INITRAMFS_INCLUDE:-all}" = "detected" ] && [ "${SMARTCARD_HAS_TPM2_TOKEN:-0}" = "0" ]; then
    return 0
fi

# Get root mapper and device info
get_root_mapper_name() {
    for tok in $(cat /proc/cmdline); do
        case "$tok" in root=/dev/mapper/*) echo "${tok#root=/dev/mapper/}"; return 0 ;; esac
    done
    return 1
}

resolve_mapping() {
    preferred_target="$1"
    found_target=""
    found_source=""

    [ -r /etc/crypttab ] || return 1

    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        set -- $line
        [ "$#" -ge 2 ] || continue
        if [ -z "$found_target" ]; then
            found_target="$1"; found_source="$2"
            [ -z "$preferred_target" ] && break
        fi
        if [ "$1" = "$preferred_target" ]; then
            found_target="$1"; found_source="$2"
            break
        fi
    done < /etc/crypttab

    [ -n "$found_target" ] && printf '%s|%s\n' "$found_target" "$found_source"
    return 0
}

auto_detect_tpm2_token() {
    _dev="$1"
    _i=0
    while [ "$_i" -lt 32 ]; do
        _json="$(cryptsetup token export --token-id "$_i" "$_dev" 2>/dev/null || true)"
        if [ -n "$_json" ]; then
            _type="$(printf '%s' "$_json" | tr -d '\n' | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')"
            if [ "$_type" = "systemd-tpm2" ]; then
                echo "$_i"
                return 0
            fi
        fi
        _i=$(( _i + 1 ))
    done
    return 1
}

find_tpm_plugin_dir() {
    for _dir in /usr/lib/*/cryptsetup /usr/lib64/cryptsetup; do
        [ -f "$_dir/libcryptsetup-token-systemd-tpm2.so" ] && echo "$_dir" && return 0
    done
    return 1
}

wait_for_tpm_device() {
    _try=0
    while [ "$_try" -lt 10 ]; do
        for _node in /dev/tpmrm[0-9]* /dev/tpm[0-9]*; do
            [ -c "$_node" ] && return 0
        done
        _try=$(( _try + 1 ))
        sleep 1
    done
    return 1
}

mapping="$(resolve_mapping "$(get_root_mapper_name)" || true)"
[ -z "$mapping" ] && return 0

CRYPTROOT_NAME="${mapping%%|*}"
CRYPTROOT_SOURCE="${mapping#*|}"

if cryptsetup status "$CRYPTROOT_NAME" >/dev/null 2>&1; then
    return 0
fi

DEV="$(_resolve_dev_hook "$CRYPTROOT_SOURCE" 2>/dev/null || true)"
[ -b "$DEV" ] || return 0

TOKEN_ID="$(auto_detect_tpm2_token "$DEV" || true)"
[ -z "$TOKEN_ID" ] && return 0

PLUGIN_DIR="$(find_tpm_plugin_dir || true)"
[ -z "$PLUGIN_DIR" ] && return 0

if ! wait_for_tpm_device; then
    return 0
fi

cryptsetup luksOpen \
    --token-only \
    --token-type systemd-tpm2 \
    --token-id "$TOKEN_ID" \
    --external-tokens-path "$PLUGIN_DIR" \
    "$DEV" "$CRYPTROOT_NAME" 2>/dev/null || true

return 0
