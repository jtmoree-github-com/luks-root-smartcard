# Debug Guide for smartcard-root

When troubleshooting LUKS root unlock or the smartcard integration, debug output helps trace what's happening during boot. This guide covers **all available debug methods**, from basic to advanced.

---

## 🚀 QUICK START: Enable Debug Output

### Method 1: Temporary Debug (GRUB Bootloader - Classic Systems Only)

**Only works with traditional GRUB bootloader, NOT with UKI.**

```bash
# At GRUB menu during boot:
# 1. Press 'e' to edit the boot entry
# 2. Add to the kernel line:
#    rd.debug=1  smartcard-root.debug=1
# 3. Press Ctrl+X to boot with these parameters
```

**Limitations:**
- ❌ Does NOT work with Unified Kernel Images (UKI)
- ❌ Cannot persist across reboots
- ✅ Useful for one-time troubleshooting

### Method 2: Persistent Debug with TPM2 Sealed Flag (UKI Only)

**Modern approach for UKI systems with TPM2.**

```bash
# One-time setup:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal create

# Enable debug (persists across boots):
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal enable

# Disable debug later:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal disable
```

**Advantages:**
- ✅ Works with UKI (locked kernel parameters)
- ✅ Persistent across reboots
- ✅ Cryptographically sealed to system state
- ⚠️ Requires working TPM2

**When to use:**
- UKI systems with TPM2
- Need persistent debug across reboots
- Want security: debug is disabled if kernel/firmware modified

👉 **See [TPM2_SEAL.md](./TPM2_SEAL.md) for full TPM2 documentation.**

### Method 3: Compile-Time Debug (Development Only)

```bash
# Edit the source script to hardcode debug:
# In: scripts/smartcard-root-tpm2.sh (or your boot script)
# Set: DEBUG=1  (or DEBUG=true)

# Rebuild initramfs:
sudo dracut -f

# Reboot to apply
sudo reboot
```

**Limitations:**
- ⚠️ Changes the build
- ⚠️ Can't toggle without rebuilding
- ✅ Always works (no TPM required)
- ✅ Good for development/testing

---

## 🔍 DEBUG OUTPUT: Where to Look

### 1. Initramfs Boot Messages (Real-Time)
During boot, debug output appears on the console. Look for lines like:
```
[DEBUG] smartcard-root-tpm2: Checking for TPM seal...
[DEBUG] smartcard-root-tpm2: DEBUG_ENABLED=1
[DEBUG] smartcard-root-tpm2: Attempting token unlock...
```

### 2. Kernel Message Buffer
```bash
# View messages from last boot:
sudo dmesg | grep -i smartcard-root
sudo dmesg | grep -i "DEBUG"
```

### 3. systemd Journal
```bash
# If systemd-journald is running:
sudo journalctl -u smartcard-root -n 100 --no-pager

# Follow live during boot (if system reaches systemd):
sudo journalctl -f -u smartcard-root
```

### 4. /dev/kmsg (Direct Kernel Messages)
```bash
# Real-time kernel messages during boot:
sudo cat /dev/kmsg | grep smartcard-root
```

### 5. Temporary Log File (Manual Debugging)
Add this to your boot script for persistent logging:

```bash
# In dracut hook (smartcard-root-tpm2.sh):
exec 2>&1 >> /run/smartcard-root-debug.log
```

View after boot:
```bash
sudo cat /run/smartcard-root-debug.log
```

---

## 📋 Common Debug Scenarios

### Scenario 1: "LUKS Unlock Failed - No Token Found"

**What to check:**
```bash
# 1. Are you using the right token type?
sudo systemctl status systemd-cryptsetup@*

# 2. Check if TPM is detected:
tpm2_getcap handles-persistent
sudo tpm2_pcrread sha256

# 3. Check FIDO2/PKCS11 token presence:
systemd-cryptenroll --fido2-device=list
systemd-cryptenroll --pkcs11-provider=list

# 4. View the actual token types on your LUKS device:
sudo cryptsetup token list /dev/mapper/root
```

**Debug steps:**
```bash
# Enable debug and reboot:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal enable
sudo reboot

# After failed boot, check messages:
sudo dmesg | tail -50
sudo journalctl -xe
```

### Scenario 2: "TPM Seal Not Unsealing"

**Symptoms:**
- TPM seal exists but debug isn't enabled
- After kernel update, debug stopped working

**What to check:**
```bash
# Check seal status:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status

# Verify TPM seal exists:
tpm2_getcap handles-persistent | grep 0x81000001

# Check PCR values changed:
tpm2_pcrread sha256:7,11

# Audit seal integrity:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal audit
```

**Fix:**
```bash
# After kernel/firmware update, rotate the seal:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal rotate

# Verify rotation worked:
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status
```

### Scenario 3: "TPM Device Not Found"

**Symptoms:**
```
tpm2_unseal: No such file or directory
/dev/tpm* not found
```

**Root causes:**
- TPM not enabled in BIOS
- TPM kernel module not loaded
- tpm2-tools not installed

**Fix:**
```bash
# 1. Check BIOS: Enable TPM 2.0 (varies by manufacturer)

# 2. Load TPM kernel module:
sudo modprobe tpm_tis     # AMD systems
sudo modprobe tpm_crb     # Intel systems

# 3. Verify TPM presence:
ls -la /dev/tpm* /dev/tpmrm*

# 4. Install tpm2-tools if missing:
sudo apt-get install tpm2-tools

# 5. Test TPM:
tpm2_getcap handles-persistent
```

### Scenario 4: "No Debug Output - Silent Boot"

**If nothing appears even with debug enabled:**

1. **Check if debug is actually enabled:**
   ```bash
   sudo /usr/local/bin/smartcard-root-tpm2-debug-seal status
   ```

2. **Boot with temporary kernel parameter:**
   ```bash
   # GRUB: Add rd.debug=1
   # This forces systemd debugging (different from our TPM seal)
   ```

3. **Check initramfs includes debug script:**
   ```bash
   # Verify dracut module is installed:
   ls /usr/lib/dracut/modules.d/90smartcard-root/
   
   # Extract and inspect initramfs:
   sudo lsinitrd /boot/initramfs-*.img | grep smartcard-root
   ```

4. **Rebuild if needed:**
   ```bash
   sudo dracut -f
   sudo reboot
   ```

---

## 🔧 Advanced: Debugging Without TPM

If TPM is broken or unavailable:

### Fallback Chain
```
1. Kernel cmdline parameter (rd.debug=1)
   └─ Works with GRUB; NOT with UKI
   
2. TPM2 sealed flag (if available)
   └─ Works with UKI; requires TPM
   └─ Silently skips if TPM unavailable
   
3. Compile-time hardcoded DEBUG=1
   └─ Last resort; always works
   └─ Requires rebuild
```

### Token Types (Independent of Debug)
Debug mode is **orthogonal** to which token type unlocks LUKS:

```
Token Type         Debug Available?
─────────────────────────────────
TPM2 seal          ✅ (via TPM unseal)
FIDO2              ✅ (if cmdline/compile-time set)
PKCS11             ✅ (if cmdline/compile-time set)
GPG                ✅ (if cmdline/compile-time set)
```

**Key point:** Even if TPM debug fails, FIDO2/PKCS11/GPG token unlock continues normally—debug is just disabled, not an error.

---

## 📖 Debug Methods Summary

| Method | UKI? | Persistent? | Secure? | Easy? | Use When |
|--------|------|-------------|---------|-------|----------|
| GRUB kernel param | ❌ | ❌ | ✅ | ✅ | Classic systems, one-time debug |
| TPM2 sealed | ✅ | ✅ | ✅ | ✅ | UKI with TPM2, need persistence |
| Compile-time | ✅ | ✅ | ❌ | ⚠️ | Development, TPM unavailable |

---

## 🔐 Security Considerations

### TPM2 Sealed Debug
- ✅ **Protected:** Debug disabled if kernel/firmware modified
- ✅ **Verified:** Cryptographic PCR binding
- ⚠️ **Not protected:** Runtime attacks (once booted with debug, kernel can't disable)

### Kernel Parameter Debug
- ✅ **Simple:** Easy to enable/disable
- ⚠️ **Temporary:** Only for current boot
- ⚠️ **Not with UKI:** Parameters are locked in UKI

### Compile-Time Debug
- ✅ **Always works:** No dependencies
- ⚠️ **Permanent:** Must rebuild to disable
- ⚠️ **Visible:** Can't hide debug in production

---

## 🐛 Troubleshooting Debug Itself

### "Debug works locally but not on production boot"

**Likely cause:** You're using GRUB kernel params, but boot was switched to UKI.

**Fix:** Use TPM2 sealed method instead (persistent across UKI).

### "Seal keeps failing with 'PCRs don't match'"

**Likely cause:** System state changed (kernel update, BIOS change, Secure Boot toggle).

**Fix:** 
```bash
sudo /usr/local/bin/smartcard-root-tpm2-debug-seal rotate
```

### "I see debug output in dmesg but not in journalctl"

**Likely cause:** systemd-journald not running during boot (journalctl only captures *after* systemd starts).

**Fix:** Check `/dev/kmsg` directly during boot, or use serial console.

---

## 📚 Related Documentation

- [TPM2_SEAL.md](./TPM2_SEAL.md) — Comprehensive TPM2 sealing reference
- [../SETUP.md](../SETUP.md) — Initial system setup
- [../IMPLEMENTATION_SUMMARY.md](../IMPLEMENTATION_SUMMARY.md) — Implementation details
- [../ARCHITECTURE_DIAGRAMS.md](../ARCHITECTURE_DIAGRAMS.md) — Boot flow diagrams

---

## 🔗 External References

- [systemd Measured Boot](https://systemd.io/MEASURED_BOOT/)
- [TPM2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)
- [dracut Documentation](https://dracut.wiki.kernel.org/)
- [tpm2-tools GitHub](https://github.com/tpm2-software/tpm2-tools)
