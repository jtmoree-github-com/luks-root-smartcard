#!/bin/sh
# dracut hook: smartcard-root-tpm2-debug
# Runtime check for TPM2-sealed debug flag during early boot
# Allows toggling debug mode without rebuilding UKI or modifying kernel cmdline

. /lib/smartcard-common-lib.sh

# Check if debug is already enabled via kernel cmdline
DEBUG_ENABLED_CMDLINE=0
for _dbg_tok in $(cat /proc/cmdline 2>/dev/null); do
  case "$_dbg_tok" in
    rd.debug|rd.debug=1|rd.debug=true|smartcard-root.debug|smartcard-root.debug=1|smartcard-root.debug=true)
      DEBUG_ENABLED_CMDLINE=1
      ;;
    rd.debug=0|rd.debug=false|smartcard-root.debug=0|smartcard-root.debug=false)
      DEBUG_ENABLED_CMDLINE=0
      ;;
  esac
done

# If already enabled via cmdline, don't check TPM
if [ "$DEBUG_ENABLED_CMDLINE" = "1" ]; then
  return 0
fi

# Check TPM for sealed debug flag
check_tpm_debug_seal() {
  # Verify tpm2_unseal is available
  if ! command -v tpm2_unseal >/dev/null 2>&1; then
    return 1
  fi

  # Try to unseal the debug flag from TPM handle
  # Handle 0x81000001 is standard for smartcard-root debug flag
  # Unsealing only succeeds if PCR measurements match the sealing policy
  tpm2_unseal -c 0x81000001 >/dev/null 2>&1
  return $?
}

# Attempt to enable debug via TPM seal
if check_tpm_debug_seal; then
  # Unseal succeeded - debug flag is cryptographically valid
  # Export for existing debug infrastructure to pick up
  export SMARTCARD_ROOT_DEBUG_TPM_SEAL=1
  
  # If running in systemd environment, enable verbose logging
  if [ -d /sys/firmware/efi ]; then
    export SYSTEMD_LOG_LEVEL=debug
  fi
fi

return 0
