# TPM2 Sealed Debug Mode for UKI

## Overview

When using Unified Kernel Images (UKI), you can no longer pass kernel boot parameters like `smartcard-root.debug` at the bootloader prompt. This solution uses TPM2 sealing to enable debug mode without rebuilding the UKI.

The debug flag is cryptographically bound to your system's secure boot state and kernel measurements. If someone modifies the kernel or firmware, the seal won't unseal and debug will be disabled—ensuring debug mode is only active in a trustworthy state.

## System Architecture

### Boot Sequence Diagram
```
UKI (UEFI) → Kernel + Initramfs (baked in, locked)
                        ↓
        Initramfs Pre-Mount Hooks
                        ↓
    Hook 00: smartcard-root-tpm2-debug.sh (NEW)
    └─→ tpm2_unseal -c 0x81000001
        ├─ Success (PCRs match) → export DEBUG_ENABLED=1
        └─ Failure (PCRs differ) → leave DEBUG_ENABLED=0
                        ↓
    Hook 20: smartcard-root-tpm2.sh (existing)
    └─→ Uses DEBUG_ENABLED for debug output
        └─→ LUKS unlock with token
                        ↓
        Main System Boot (with debug level set)
```

### TPM2 Seal Lifecycle
```
[SETUP]
User runs: smartcard-root-tpm2-debug-seal create
  ↓ Read current PCR 7, 11
  ↓ Create sealing policy (JSON)
  ↓ Generate TPM primary key
  ↓ Encrypt debug flag with policy
  ↓ Store at TPM handle 0x81000001 (persistent NVRAM)
  ✓ Seal created

[BOOT] (every time)
Initramfs early boot:
  ↓ tpm2_unseal -c 0x81000001
  ↓ TPM reads current PCRs
  ↓ Compare to policy
  ├─ Match → Unseal succeeds → DEBUG=1
  └─ Differ → Unseal fails → DEBUG=0

[UPDATE] (after kernel/firmware change)
User runs: smartcard-root-tpm2-debug-seal rotate
  ↓ Backup old seal
  ↓ Remove old seal from TPM
  ↓ Read NEW PCR values (they've changed!)
  ↓ Create new sealing policy
  ↓ Re-seal debug flag with new policy
  ✓ Seal updated for new system state
```

## Security Model

### Threat Protection Matrix
| Threat | Attack | PCR Check | Result |
|--------|--------|-----------|--------|
| Kernel tampering | Attacker modifies kernel file | PCR 11 | ✅ Unseal fails → DEBUG=0 |
| Initramfs modification | Attacker modifies initramfs | PCR 11 | ✅ Unseal fails → DEBUG=0 |
| Cmdline injection | Attacker adds kernel params | PCR 11 | ✅ Unseal fails → DEBUG=0 |
| Firmware downgrade | Attacker downgrades BIOS | PCR 7 | ✅ Unseal fails → DEBUG=0 |
| Secure Boot disabled | Attacker disables SecBoot | PCR 7 | ✅ Unseal fails → DEBUG=0 |
| TPM reset | Attacker resets TPM | N/A | ⚠️ Seal lost (rare) |
| Runtime privilege escalation | Attacker gets root after boot | N/A | ⚠️ Not protected |
| Physical TPM extraction | Attacker removes TPM chip | N/A | ⚠️ Lab-only attack |

### What's Protected
✅ **Kernel tampering** → PCR 11 changes → Unseal fails  
✅ **Initramfs modification** → PCR 11 changes → Unseal fails  
✅ **Kernel cmdline injection** → PCR 11 changes → Unseal fails  
✅ **Firmware downgrade** → PCR 7 changes → Unseal fails  
✅ **Secure Boot disabled** → PCR 7 changes → Unseal fails  

### What's NOT Protected
⚠️ **Runtime attacks** - Once booted with debug enabled, kernel can't re-disable  
⚠️ **TPM reset** - Rare but would destroy seal (requires recreating)  
⚠️ **Physical TPM extraction** - Lab equipment required, very expensive  

## PCR Reference & Selection

## How It Works

### Sealing Process
1. **Create a policy** that locks the debug flag to specific PCR measurements
2. **Seal the flag** using TPM2 encryption
3. **Store persistently** in TPM NVRAM at a fixed handle

### Boot Process
1. **Early boot** (initramfs): Check if TPM seal can be unsealed
2. **If unseal succeeds**: PCRs match and debug is enabled
3. **If unseal fails**: PCRs don't match; skip debug (prevents unauthorized debug)

### PCR Selection
- **PCR 7**: Secure Boot state and Machine Owner Keys (MOK)
- **PCR 11**: Unified kernel image measurement (kernel + initrd + cmdline)
- **Default policy**: `7,11` (recommended for most UKI setups)

## Quick Start

### Prerequisites
```bash
# Install tpm2-tools
sudo apt-get install tpm2-tools

# Verify TPM is available
ls -la /dev/tpm* /dev/tpmrm*
```

### Initial Setup (after first UKI boot)
```bash
# Create the sealed debug flag
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal create

# Verify it was created
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status
```

### Check Debug Status
```bash
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status
```

### Enable/Disable Debug
```bash
# Enable debug (seal is checked on next boot)
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal enable

# Disable debug (removes seal from TPM, no debug on next boot)
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal disable
```

### Rotate Seal After Kernel Update
When you update your kernel or firmware, the PCR values change. You need to rotate the seal:

```bash
# This will:
# 1. Backup the old seal
# 2. Remove the old seal from TPM
# 3. Re-seal with new PCR values
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal rotate
```

## Installation

### For Package Maintainers
1. Copy `smartcard-root-tpm2-debug-seal` to `/usr/local/bin/`
2. Make it executable: `chmod 755 /usr/local/bin/smartcard-root-tpm2-debug-seal`
3. Copy `dracut/smartcard-root-tpm2-debug.sh` to the dracut module directory
4. Update `module-setup.sh` to include the new hook

### For Development
```bash
# Install script locally
sudo cp scripts/smartcard-root-tpm2-debug-seal /usr/local/bin/
sudo chmod 755 /usr/local/bin/smartcard-root-tpm2-debug-seal

# Install dracut module
sudo cp dracut/smartcard-root-tpm2-debug.sh /usr/lib/dracut/modules.d/90smartcard-root/

# Verify installation
smartcard-root-tpm2-debug-seal --help
```

## Command Reference

### create
Creates and seals the debug flag to current system state.

```bash
sudo smartcard-root-tpm2-debug-seal create [--pcr=7,11,12] [--force]
```

**Options:**
- `--pcr=PCRs`: Comma-separated PCR list (default: `7,11`)
- `--force`: Recreate even if seal already exists

**Example:**
```bash
# Create with default PCRs (7, 11)
sudo smartcard-root-tpm2-debug-seal create

# Create with additional PCR for extra security
sudo smartcard-root-tpm2-debug-seal create --pcr=7,11,12

# Recreate (remove old seal first)
sudo smartcard-root-tpm2-debug-seal create --force
```

### enable
Marks debug as enabled and ready to check on boot.

```bash
sudo smartcard-root-tpm2-debug-seal enable
```

### disable
Removes the debug seal from TPM (disables debug on next boot).

```bash
sudo smartcard-root-tpm2-debug-seal disable
```

### status
Shows current seal status, metadata, and PCR values.

```bash
sudo smartcard-root-tpm2-debug-seal status
```

**Output includes:**
- Seal presence in TPM
- Creation metadata (date, PCRs used)
- Current PCR values
- Unseal verification result

### rotate
Updates the seal to match new system state (e.g., after kernel/firmware updates).

```bash
sudo smartcard-root-tpm2-debug-seal rotate [--pcr=7,11,12]
```

**Process:**
1. Backs up old seal to `/etc/smartcard-root-debug/backup_<timestamp>/`
2. Removes old seal from TPM
3. Reads current PCR values
4. Creates new seal with new PCR measurements

**When to use:**
- After kernel updates
- After firmware/BIOS updates
- After Secure Boot policy changes

### audit
Performs detailed audit of seal integrity and TPM state.

```bash
sudo smartcard-root-tpm2-debug-seal audit
```

**Checks:**
- Persistent TPM handles
- TPM event log entries
- Seal integrity verification

## Troubleshooting

### Debug with TPM Disabled or Not Available
**If TPM doesn't work, debug still works via these methods (in order):**

```
1. Kernel cmdline parameter (PRIMARY)
   └─ rd.debug=1  or  smartcard-root.debug=1
   └─ Can't use with UKI, but works for temporary manual testing

2. TPM2 sealed flag (OPTIONAL - this feature)
   └─ Only used if cmdline doesn't set debug
   └─ Fails gracefully if TPM unavailable

3. Compile-time settings (FALLBACK)
   └─ DEBUG hardcoded in scripts
   └─ Only if both above methods unavailable
```

**What happens if TPM fails:**
- System checks cmdline params first ✓ (still works)
- If no cmdline param, tries TPM unseal
- If TPM unavailable/fails: silently continues (returns 0, doesn't error)
- Debug stays at whatever value was set by cmdline
- LUKS unlock continues with other token types (FIDO2, PKCS11, GPG)

### Seal Not Unsealing on Boot
**Symptom:** Debug is disabled even though seal was created.

**Causes:**
- PCR values changed (kernel update, firmware change, Secure Boot config)
- TPM was reset

**Solution:**
```bash
# Check current status
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status

# If PCRs changed, rotate the seal
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal rotate

# Check event log for clues
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal audit
```

### tpm2_unseal: "No such file or directory"
**Symptom:** Error when trying to unseal on boot.

**Cause:** `tpm2-tools` not included in initramfs.

**Solution:** Ensure dracut module is installed and rebuild initramfs:
```bash
sudo update-initramfs -u
```

### TPM Device Not Found
**Symptom:** `TPM device not found`

**Cause:** TPM not enabled in BIOS or kernel module not loaded.

**Solution:**
1. Check BIOS: Enable TPM/TPM 2.0
2. Load kernel module: `sudo modprobe tpm_tis` (or `tpm_crb` for Intel)
3. Verify: `ls -la /dev/tpm*`

### Kernel Update Broke Debug
**Symptom:** Debug works, then after kernel update it stops.

**Cause:** Kernel update changed PCR 11 value.

**Solution:**
```bash
# Rotate seal to new PCR values
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal rotate
```

### "Already exists at handle"
**Symptom:** `smartcard-root-tpm2-debug-seal create` says seal already exists.

**Solution:** Use `--force` to recreate:
```bash
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal create --force
```

Or disable first:
```bash
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal disable
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal create
```

## PCR Reference

| PCR | Description | Use Case |
|-----|-------------|----------|
| 0 | Firmware/BIOS code | ⚠️ Varies across boots; avoid |
| 1 | BIOS settings | ⚠️ Changes often; avoid |
| 7 | Secure Boot state, MOK | ✅ **Recommended** for UKI |
| 9 | Kernel command line | ✅ Alternative to 11 |
| 11 | Unified kernel image (systemd) | ✅ **Recommended** for UKI |
| 12 | Kernel command line (alternative) | ✓ Defense-in-depth |

**Recommended Policies:**
- `7,11` - Standard UKI (most common)
- `7,11,12` - High security (more resistant to rollback)
- `7` - Loose (only checks Secure Boot state)

## Security Considerations

### What This Protects
✅ **Kernel tampering**: Debug disabled if kernel is modified  
✅ **Initramfs tampering**: Debug disabled if initramfs is modified  
✅ **Bootloader parameter injection**: Debug disabled if kernel cmdline modified  
✅ **Firmware downgrade**: Debug disabled if Secure Boot state changes  

### What This Does NOT Protect
⚠️ **Runtime attacks**: Once booted with debug enabled, kernel can't enforce debug disable  
⚠️ **TPM ownership**: If TPM ownership is reset, seal is lost  
⚠️ **Physical attacks**: TPM can be extracted from motherboard (but requires lab equipment)  

### Best Practices
1. **Use high-security PCR policy** (`7,11,12`) for production
2. **Rotate seal regularly** after kernel/firmware updates
3. **Audit seal status** periodically: `sudo smartcard-root-tpm2-debug-seal audit`
4. **Keep backups** of seal metadata (automatically saved in `/etc/smartcard-root-debug/`)
5. **Use Secure Boot** - ensures PCR 7 measurements are trustworthy

## Alternative Debug Workflows

### When TPM is Unavailable
This feature is **completely optional**. If TPM doesn't work, all other token types continue to function:

| Scenario | Debug Method | Status |
|----------|--------------|--------|
| TPM works | TPM2 sealed flag (this feature) | ✅ Recommended |
| TPM broken/missing | Kernel cmdline param | ✅ Still works* |
| TPM + cmdline unavailable | FIDO2/PKCS11/GPG unlock | ✅ Still works |
| All else fails | Compile-time hardcoded debug | ✅ Fallback available |

*Kernel cmdline params work with GRUB but NOT with UKI (locked params)—this is why TPM seal was added.

### Token Type Independence
Debug mode is **independent** of which token type you use for LUKS unlock:

```
Your LUKS Root Unlock Flow:
┌────────────────────────────────┐
│ 00-smartcard-root-tpm2-debug   │
│ └─→ Sets DEBUG_ENABLED          │
│     (via cmdline OR TPM seal)   │
└────────────────────────────────┘
                 ↓
┌────────────────────────────────┐
│ Token Selection (any of):      │
│ • TPM2 token                   │
│ • FIDO2 token                  │
│ • PKCS11 token                 │
│ • GPG token                    │
│ └→ Uses DEBUG_ENABLED value    │
└────────────────────────────────┘
                 ↓
┌────────────────────────────────┐
│ LUKS Unlock (with or without   │
│ debug output based on setting) │
└────────────────────────────────┘
```

**Key point:** TPM debug seal failure doesn't affect FIDO2, PKCS11, or GPG token unlock.

### Fallback Chain for Debug
```
1. Check kernel cmdline    → DEBUG=1 if param found
2. Check TPM seal (if #1 failed)    → DEBUG=1 if unseal succeeds
3. Otherwise    → DEBUG=0 (silent mode)
4. If TPM fails at any point    → Continue gracefully (no error)
```

All stages are **optional and silent on failure**.

## Integration with Existing Debug Tools

The sealed debug flag integrates seamlessly with existing infrastructure:

### Kernel Command Line (Fallback)
If you temporarily need to override TPM seal:
```bash
# Boot with kernel parameter to force debug
# (This requires manual GRUB editing; not available with UKI's locked parameters)
```

### systemd Logging
When debug is enabled via TPM seal:
```bash
# systemd will use SYSTEMD_LOG_LEVEL=debug
journalctl -u smartcard-root -n 100 --no-pager
```

### Initramfs Debug Output
All smartcard-root debug messages go to:
- `/dev/kmsg` (kernel message buffer)
- stderr (captured by dracut)
- systemd journal (if systemd-journald is running)

## Advanced: Manual Seal Management

### Read Current PCR Values
```bash
tpm2_pcrread sha256
```

### Create Seal Manually
```bash
# Create policy
tpm2_pcrread -l sha256:7,11 -L /tmp/policy.json

# Create primary context
tpm2_createprimary -C e -g sha256 -G rsa -c /tmp/primary.ctx

# Seal debug flag
echo -n "SMARTCARD_ROOT_DEBUG_TPM2_SEAL" | \
  tpm2_create -C /tmp/primary.ctx \
    -L /tmp/policy.json -i - -c /tmp/sealed.ctx

# Persist to TPM
tpm2_evictcontrol -C o -c /tmp/sealed.ctx 0x81000001
```

### Verify Seal Integrity
```bash
tpm2_unseal -c 0x81000001
# Should output: SMARTCARD_ROOT_DEBUG_TPM2_SEAL
```

## Files and Locations

| File | Purpose |
|------|---------|
| `/usr/local/bin/smartcard-root-tpm2-debug-seal` | Main management script |
| `/usr/lib/dracut/modules.d/90smartcard-root/smartcard-root-tpm2-debug.sh` | Dracut hook (early boot check) |
| `/etc/smartcard-root-debug/` | State directory (metadata, backups) |
| `/etc/smartcard-root-debug/seal_metadata.txt` | Seal creation info |
| `/etc/smartcard-root-debug/pcr_state_at_creation.bin` | PCR state when seal was created |
| `/etc/smartcard-root-debug/backup_*/` | Rotated seal backups |

## Related Documentation

- [TPM2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)
- [systemd Measured Boot](https://systemd.io/UNIFIED_KERNEL_IMAGE/)
- [Secure Boot and PCRs](https://uapi-group.org/specifications/specs/linux_tpm_pcr_registry/)
- [tpm2-tools Documentation](https://github.com/tpm2-software/tpm2-tools/wiki)

## License

Same as luks-root-smartcard project.
