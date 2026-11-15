#!/bin/sh
# dracut hook: smartcard-root-token-detection
# Auto-detects smartcard tokens in LUKS2 root device and exports hints for unlock handlers

. /lib/smartcard-common-lib.sh

# Load configuration for token detection mode
_load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE" "all"

# Source crypttab to get device mappings
CRYPTROOT_NAME=""
CRYPTROOT_SOURCE=""

# Try to find root mapping from crypttab
if [ -r /etc/crypttab ]; then
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        set -- $line
        if [ "$#" -ge 2 ]; then
            CRYPTROOT_NAME="$1"
            CRYPTROOT_SOURCE="$2"
            break
        fi
    done < /etc/crypttab
fi

if [ -z "$CRYPTROOT_SOURCE" ]; then
    return 0
fi

# Resolve device
DEV="$(_resolve_dev_hook "$CRYPTROOT_SOURCE" 2>/dev/null || true)"
if [ ! -b "$DEV" ]; then
    return 0
fi

# Detect token types and store hints in environment for unlock hooks
if _has_token "$DEV" "systemd-tpm2"; then
    export SMARTCARD_HAS_TPM2_TOKEN=1
fi

if _has_token "$DEV" "systemd-fido2"; then
    export SMARTCARD_HAS_FIDO2_TOKEN=1
fi

if _has_token "$DEV" "systemd-pkcs11"; then
    export SMARTCARD_HAS_PKCS11_TOKEN=1
fi

if _has_token "$DEV" "gpg-token"; then
    export SMARTCARD_HAS_GPG_TOKEN=1
fi

return 0
