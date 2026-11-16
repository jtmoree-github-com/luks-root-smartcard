#!/bin/sh
# dracut hook: smartcard-root-gpg
# Runtime smartcard GPG token unlock for LUKS2 root device

. /lib/smartcard-common-lib.sh

_load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE" "all"

if [ "${SMARTCARD_INITRAMFS_INCLUDE:-all}" = "detected" ] && [ "${SMARTCARD_HAS_GPG_TOKEN:-0}" = "0" ]; then
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

auto_detect_gpg_token() {
    _dev="$1"
    _i=0
    while [ "$_i" -lt 32 ]; do
        _json="$(cryptsetup token export --token-id "$_i" "$_dev" 2>/dev/null || true)"
        if [ -n "$_json" ]; then
            _type="$(printf '%s' "$_json" | tr -d '\n' | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')"
            if [ "$_type" = "gpg-token" ]; then
                echo "$_i"
                return 0
            fi
        fi
        _i=$(( _i + 1 ))
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

TOKEN_ID="$(auto_detect_gpg_token "$DEV" || true)"
[ -z "$TOKEN_ID" ] && return 0

# Minimal GPG unlock via cryptsetup (full interaction handled by standard cryptroot if this fails)
cryptsetup luksOpen \
    --token-only \
    --external-tokens-path /usr/lib/cryptsetup \
    "$DEV" "$CRYPTROOT_NAME" 2>/dev/null || true

return 0
