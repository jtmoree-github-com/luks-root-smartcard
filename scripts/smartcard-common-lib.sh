#!/bin/sh
# smartcard-common-lib.sh - Shared functions for initramfs and dracut hooks
# Provides device resolution, token detection, and configuration utilities.
# Sourced by both initramfs hooks and dracut module-setup scripts.

# Resolve device path from crypttab format (UUID=, LABEL=, etc.) to actual device.
# Used identically across all token-type hooks.
#
# Usage: dev="$(_resolve_dev_hook "$device_spec")"
#
_resolve_dev_hook() {
    case "$1" in
        UUID=*)      blkid -U "${1#UUID=}" 2>/dev/null ;;
        LABEL=*)     blkid -L "${1#LABEL=}" 2>/dev/null ;;
        PARTUUID=*)  echo "/dev/disk/by-partuuid/${1#PARTUUID=}" ;;
        PARTLABEL=*) echo "/dev/disk/by-partlabel/${1#PARTLABEL=}" ;;
        *)           echo "$1" ;;
    esac
}

# Scan LUKS2 header for a specific token type.
# Returns 0 if found, 1 if not.
#
# Usage: if _has_token "$device" "systemd-tpm2"; then ...
#
_has_token() {
    _hdev="$1"
    _token_type="$2"
    _hi=0
    while [ "$_hi" -lt 32 ]; do
        _hjson="$(cryptsetup token export --token-id "$_hi" "$_hdev" 2>/dev/null || true)"
        if [ -n "$_hjson" ] && printf '%s' "$_hjson" | grep -q "\"type\":\"$_token_type\""; then
            return 0
        fi
        _hi=$(( _hi + 1 ))
    done
    return 1
}

# Convenience wrappers for specific token types
_has_systemd_tpm2_token() {
    _has_token "$1" "systemd-tpm2"
}

_has_systemd_fido2_token() {
    _has_token "$1" "systemd-fido2"
}

_has_systemd_pkcs11_token() {
    _has_token "$1" "systemd-pkcs11"
}

_has_gpg_token() {
    _has_token "$1" "gpg-token"
}

# Determine if any crypttab entry uses a given token type.
# Scans crypttab and tests each device for the token.
# Returns 0 if at least one entry uses the token, 1 otherwise.
#
# Usage: if _uses_token_type "systemd-tpm2"; then include_assets=1; fi
#
_uses_token_type() {
    _token_type="$1"
    _crypttab="${TABFILE:-/etc/crypttab}"
    
    [ -f "$_crypttab" ] || return 1
    
    while IFS= read -r _ctline; do
        case "$_ctline" in ''|'#'*) continue ;; esac
        set -- $_ctline
        [ "$#" -ge 2 ] || continue
        _hdev="$(_resolve_dev_hook "$2" 2>/dev/null || true)"
        if [ -b "$_hdev" ]; then
            if _has_token "$_hdev" "$_token_type"; then
                return 0
            fi
        else
            # Device cannot be resolved at build time; include conservatively
            return 0
        fi
    done < "$_crypttab"
    
    return 1
}

# Load per-workflow inclusion mode from config file.
# Sets SMARTCARD_INITRAMFS_INCLUDE to "all" or "detected".
#
# Usage: _load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE"
#
_load_inclusion_config() {
    _var_name="$1"
    _default="${2:-all}"
    
    # Environment variable takes precedence
    eval "_current=\$$_var_name"
    if [ -n "$_current" ]; then
        return 0
    fi
    
    # Fall back to config file
    if [ -r /etc/luks-root-smartcard/initramfs.conf ]; then
        . /etc/luks-root-smartcard/initramfs.conf
    fi
    
    # Apply default if still unset
    eval "$_var_name=\${$_var_name:-$_default}"
}

# Determine whether to include assets for a given token type.
# Respects both SMARTCARD_INITRAMFS_INCLUDE config and detected tokens.
#
# Usage: if _should_include_token_assets "systemd-tpm2"; then echo "include"; fi
#
_should_include_token_assets() {
    _token_type="$1"
    _inclusion_mode="${SMARTCARD_INITRAMFS_INCLUDE:-all}"
    
    case "$_inclusion_mode" in
        all)
            return 0
            ;;
        detected)
            if _uses_token_type "$_token_type"; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            # Unknown mode; default to "all" for safety
            return 0
            ;;
    esac
}

# Copy library dependencies discovered via ldd.
# Adapter-agnostic: requires the caller to provide copy_func (copy_exec or inst).
#
# Usage: _copy_ldd_deps "$copy_exec_or_inst" "/path/to/binary.so"
#
_copy_ldd_deps() {
    _copy_func="$1"
    _binary="$2"
    
    ldd "$_binary" 2>/dev/null \
        | awk '/=> \/|^\// {print $(NF-1)}' \
        | while IFS= read -r so; do
            [ -f "$so" ] && "$_copy_func" "$so"
        done
}

# Common setup for cryptsetup token plugin copying.
# Caller must provide _copy_func (copy_exec for initramfs, inst for dracut).
#
# Usage: _copy_cryptsetup_plugin "$copy_exec" "systemd-tpm2" "tpm2_plugin_copied"
#
# Returns 0 if plugin found and copied, 1 otherwise.
_copy_cryptsetup_plugin() {
    _copy_func="$1"
    _plugin_type="$2"
    
    _plugin_copied=false
    case "$_plugin_type" in
        systemd-tpm2)
            for plugin in \
                /usr/lib/*/cryptsetup/libcryptsetup-token-systemd-tpm2.so \
                /usr/lib64/cryptsetup/libcryptsetup-token-systemd-tpm2.so; do
                [ -f "$plugin" ] || continue
                "$_copy_func" "$plugin"
                _plugin_copied=true
                _copy_ldd_deps "$_copy_func" "$plugin"
                break
            done
            ;;
        systemd-fido2)
            for plugin in \
                /usr/lib/*/cryptsetup/libcryptsetup-token-systemd-fido2.so \
                /usr/lib64/cryptsetup/libcryptsetup-token-systemd-fido2.so; do
                [ -f "$plugin" ] || continue
                "$_copy_func" "$plugin"
                _plugin_copied=true
                _copy_ldd_deps "$_copy_func" "$plugin"
                break
            done
            ;;
        systemd-pkcs11)
            for plugin in \
                /usr/lib/*/cryptsetup/libcryptsetup-token-systemd-pkcs11.so \
                /usr/lib64/cryptsetup/libcryptsetup-token-systemd-pkcs11.so \
                /lib/*/cryptsetup/libcryptsetup-token-systemd-pkcs11.so \
                /lib64/cryptsetup/libcryptsetup-token-systemd-pkcs11.so; do
                [ -f "$plugin" ] || continue
                "$_copy_func" "$plugin"
                _plugin_copied=true
                _copy_ldd_deps "$_copy_func" "$plugin"
                break
            done
            ;;
    esac
    
    if [ "$_plugin_copied" = true ]; then
        return 0
    else
        return 1
    fi
}

# Find the first available binary from a list of candidates.
# Useful for tools that may be in different paths on different systems.
#
# Usage: bin="$(_find_binary_path /usr/bin/gpg /bin/gpg)"
#
_find_binary_path() {
    for _bin in "$@"; do
        if [ -x "$_bin" ]; then
            echo "$_bin"
            return 0
        fi
    done
    return 1
}

# GPG-specific helpers for smartcard-root-gpg hook

# Resolve the GPG source home directory for public key import.
# Checks (in order): explicit SMARTCARD_GPG_SOURCE_HOME, 
# SMARTCARD_GPG_SOURCE_USER, SUDO_USER, or $HOME.
#
# Usage: src_home="$(_resolve_gpg_source_homedir)" || exit 1
#
_resolve_gpg_source_homedir() {
    if [ -n "${SMARTCARD_GPG_SOURCE_HOME:-}" ]; then
        printf '%s\n' "$SMARTCARD_GPG_SOURCE_HOME"
        return 0
    fi
    if [ -n "${SMARTCARD_GPG_SOURCE_USER:-}" ]; then
        _src_home="$(getent passwd "$SMARTCARD_GPG_SOURCE_USER" 2>/dev/null | cut -d: -f6)"
        if [ -n "$_src_home" ]; then
            printf '%s\n' "$_src_home/.gnupg"
            return 0
        fi
    fi
    if [ -n "${HOME:-}" ]; then
        printf '%s\n' "$HOME/.gnupg"
        return 0
    fi
    return 1
}

# Import public keys from system keyring into initramfs GNUPGHOME.
# Requires both source and destination paths to exist.
#
# Usage: _import_user_keyring_pubkeys_into_initramfs "$dest_home" || exit 1
#
_import_user_keyring_pubkeys_into_initramfs() {
    _dest_home="$1"
    _source_home="$(_resolve_gpg_source_homedir || true)"
    if [ -z "$_source_home" ] || [ ! -d "$_source_home" ]; then
        echo "WARNING: no usable GPG source keyring found for gpg-token import (SMARTCARD_GPG_SOURCE_HOME/SMARTCARD_GPG_SOURCE_USER)" >&2
        return 1
    fi

    _tmp_export="$(mktemp /tmp/smartcard-gpg-export.XXXXXX)"
    if ! /usr/bin/gpg --no-options --batch --no-tty --homedir "$_source_home" --export >"$_tmp_export" 2>/dev/null; then
        rm -f "$_tmp_export"
        echo "WARNING: failed exporting public keys from source keyring: $_source_home" >&2
        return 1
    fi
    if [ ! -s "$_tmp_export" ]; then
        rm -f "$_tmp_export"
        echo "WARNING: source keyring has no exportable public keys: $_source_home" >&2
        return 1
    fi

    if ! /usr/bin/gpg --no-options --no-autostart --trust-model=always \
        --quiet --batch --no-tty --logger-file=/dev/null \
        --homedir="$_dest_home" --import <"$_tmp_export"; then
        rm -f "$_tmp_export"
        echo "WARNING: failed importing source keyring pubkeys into initramfs GNUPGHOME" >&2
        return 1
    fi

    rm -f "$_tmp_export"
    return 0
}

