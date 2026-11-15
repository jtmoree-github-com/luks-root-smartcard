#!/bin/bash
# dracut module for luks-root-smartcard
# Provides smartcard/token unlock hooks for LUKS root volume encryption.
# Shares code with initramfs-tools hooks via smartcard-common-lib.sh

check() {
    # Only load module if cryptsetup is present
    require_binaries cryptsetup || return 1
    return 0
}

depends() {
    echo crypt
}

install() {
    inst_simple /usr/share/luks-root-smartcard/smartcard-common-lib.sh
    
    # Install common init scripts
    inst_hook pre-mount 01 "$moddir/smartcard-root-common.sh"
    inst_hook pre-mount 10 "$moddir/smartcard-root-token-detection.sh"
    
    # Install per-token unlock hooks (ordered by preference)
    inst_hook pre-mount 20 "$moddir/smartcard-root-tpm2.sh"
    inst_hook pre-mount 21 "$moddir/smartcard-root-fido2.sh"
    inst_hook pre-mount 22 "$moddir/smartcard-root-pkcs11.sh"
    inst_hook pre-mount 23 "$moddir/smartcard-root-gpg.sh"
    
    # Install cleanup hooks
    inst_hook cleanup 99 "$moddir/smartcard-root-cleanup.sh"
}

installkernel() {
    # TPM and HID modules for smartcard readers
    hostonly="" instmods tpm tpm_tis tpm_tis_core tpm_crb
    hostonly="" instmods hid hid_generic usbhid hidraw
}
