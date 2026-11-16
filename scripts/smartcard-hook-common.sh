#!/bin/sh
# smartcard-hook-common.sh - Initramfs-specific hook utilities
# Wraps smartcard-common-lib.sh with initramfs-tools hook-functions.
# Sourced by initramfs hook scripts to provide adapter-specific helpers.

# This file should only be sourced by initramfs hooks after they have
# sourced /usr/share/initramfs-tools/hook-functions and smartcard-common-lib.sh

# Adapter for copy_exec compatibility with smartcard-common-lib.
# Used to pass copy_exec to shared functions expecting a copy function.
_initramfs_copy() {
    copy_exec "$1"
}

# Install a binary and all its ldd dependencies into the initramfs.
# Combines the standard copy_exec with shared _copy_ldd_deps.
#
# Usage: _copy_exec_with_deps "/usr/bin/gpg"
#
_copy_exec_with_deps() {
    copy_exec "$1"
    _copy_ldd_deps _initramfs_copy "$1"
}

# Attempt to copy a cryptsetup token plugin and warn if not found.
# Uses initramfs adapter context (copy_exec, DESTDIR, etc).
#
# Usage: if _copy_token_plugin "systemd-tpm2"; then echo "found"; else echo "missing"; fi
#
_copy_token_plugin() {
    _plugin_type="$1"
    if _copy_cryptsetup_plugin _initramfs_copy "$_plugin_type"; then
        return 0
    else
        return 1
    fi
}

# Copy directory tree preserving structure into DESTDIR.
# Wrapper for initramfs cp -a usage.
#
# Usage: _copy_dir_tree "/usr/share/opensc" "/usr/share"
#
_copy_dir_tree() {
    _src="$1"
    _dest_parent="$2"
    [ -d "$_src" ] || return 1
    [ -d "$DESTDIR$_dest_parent" ] || mkdir -p "$DESTDIR$_dest_parent"
    cp -a "$_src" "$DESTDIR$_dest_parent/"
}

# Conditionally copy a file with a warning if missing.
# Wrapper for copy_file with logging.
#
# Usage: _copy_file_maybe "/etc/reader.conf"
#
_copy_file_maybe() {
    _file="$1"
    _type="${2:-misc}"
    [ -f "$_file" ] || return 1
    copy_file "$_type" "$_file" || true
}

# Determine if we should proceed with hook asset inclusion.
# Checks SMARTCARD_INITRAMFS_INCLUDE config and token detection.
#
# Usage: if _should_include_assets "systemd-tpm2"; then ... else exit 0; fi
#
_should_include_assets() {
    _token_type="$1"
    _load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE" "all"
    if ! _should_include_token_assets "$_token_type"; then
        return 1
    fi
    return 0
}
