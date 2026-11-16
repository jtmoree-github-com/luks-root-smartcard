# Shared Code Architecture for Initramfs and Dracut Hooks

## Overview

These tools use smartcard tokens for root LUKS2 volume unlock for both **initramfs-tools** (Debian/Ubuntu) and **dracut** (systemd-based systems). To avoid code duplication and ensure consistent behavior across boot systems, the hooks share common shell libraries and functions.

## Directory Structure

```
luks-root-smartcard/
├── scripts/
│   ├── smartcard-common-lib.sh        # Shared core functions (device resolution, token detection)
│   └── smartcard-hook-common.sh       # Initramfs-specific adapter wrappers
├── initramfs/
│   ├── hooks/
│   │   ├── smartcard-root-common      # Common assets (realpath)
│   │   ├── smartcard-root-tpm2        # TPM2 asset inclusion hook
│   │   ├── smartcard-root-fido2       # FIDO2 asset inclusion hook
│   │   ├── smartcard-root-pkcs11      # PKCS#11 asset inclusion hook
│   │   └── smartcard-root-gpg         # GPG asset inclusion hook
│   ├── local-top/
│   │   ├── 00-smartcard-root-tpm2     # TPM2 runtime unlock script
│   │   ├── 05-smartcard-root-fido2    # FIDO2 runtime unlock script (unused; systemd-pkcs11 takes precedence)
│   │   ├── 10-smartcard-root-pkcs11   # PKCS#11 runtime unlock script (unused; systemd-pkcs11 takes precedence)
│   │   └── 20-smartcard-root-gpg      # GPG runtime unlock script (unused; cryptsetup token takes precedence)
│   └── local-bottom/
│       └── smartcard-root             # Cleanup daemons and state
└── dracut/
    ├── module-setup.sh                # Dracut module declaration
    ├── smartcard-root-common.sh       # Common setup (realpath availability check)
    ├── smartcard-root-token-detection.sh  # Token type detection
    ├── smartcard-root-tpm2.sh         # TPM2 runtime unlock hook
    ├── smartcard-root-fido2.sh        # FIDO2 runtime unlock hook
    ├── smartcard-root-pkcs11.sh       # PKCS#11 runtime unlock hook
    ├── smartcard-root-gpg.sh          # GPG runtime unlock hook
    └── smartcard-root-cleanup.sh      # Cleanup daemons and state
```

## Shared Libraries

### `scripts/smartcard-common-lib.sh`

Contains **system-agnostic** functions used identically by both hook systems:

#### Device Resolution
- `_resolve_dev_hook(device_spec)` — Convert crypttab device specs (UUID=, LABEL=, etc.) to actual block device paths

#### Token Detection
- `_has_token(device, token_type)` — Check if a LUKS2 header contains a specific token type
- `_has_systemd_tpm2_token(device)` — Convenience wrapper for TPM2 token detection
- `_has_systemd_fido2_token(device)` — Convenience wrapper for FIDO2 token detection
- `_has_systemd_pkcs11_token(device)` — Convenience wrapper for PKCS#11 token detection
- `_has_gpg_token(device)` — Convenience wrapper for GPG token detection

#### Configuration Loading
- `_load_inclusion_config(var_name)` — Load asset inclusion mode from `/etc/luks-root-smartcard/initramfs.conf` or environment
- `_should_include_token_assets(token_type)` — Decide whether to include assets based on inclusion mode ("all" vs "detected")

#### Cryptsetup Plugin Handling
- `_uses_token_type(token_type)` — Scan crypttab to detect if any device uses a specific token type
- `_copy_cryptsetup_plugin(copy_func, plugin_type)` — Generic plugin copying (adapter-agnostic)
- `_copy_ldd_deps(copy_func, binary)` — Copy library dependencies via ldd

#### Utilities
- `_find_binary_path(...)` — Find first available binary from a list of candidates
- `_resolve_gpg_source_homedir()` — Locate GPG source keyring for public key import
- `_import_user_keyring_pubkeys_into_initramfs(dest_home)` — Import GPG public keys for boot-time verification

### `scripts/smartcard-hook-common.sh`

Contains **initramfs-tools-specific** wrappers and adapters:

- `_initramfs_copy(binary)` — Adapter wrapper for `copy_exec()` to use with shared functions
- `_copy_exec_with_deps(binary)` — Copy binary and its ldd dependencies
- `_copy_token_plugin(plugin_type)` — Initramfs-specific plugin copying
- `_copy_dir_tree(src, dest_parent)` — Copy directory tree into DESTDIR
- `_copy_file_maybe(file, type)` — Conditionally copy file with warnings
- `_should_include_assets(token_type)` — Integration helper combining config and token detection

## Initramfs Hooks Usage

### Build-Time (Hook Execution)

Each initramfs hook sources the shared libraries:

```sh
. /usr/share/initramfs-tools/hook-functions
. /usr/share/luks-root-smartcard/smartcard-common-lib.sh
```

Then uses shared functions to:
1. Determine if assets should be included (`_load_inclusion_config`, `_should_include_token_assets`)
2. Detect tokens in crypttab devices (`_uses_token_type`)
3. Copy plugins and dependencies (`_copy_cryptsetup_plugin`, `_copy_ldd_deps`)

Example (smartcard-root-tpm2):
```sh
_load_inclusion_config "SMARTCARD_INITRAMFS_INCLUDE" "all"
if [ "${SMARTCARD_INITRAMFS_INCLUDE:-all}" = "detected" ] && ! _uses_token_type "systemd-tpm2"; then
    exit 0
fi

if ! _copy_cryptsetup_plugin copy_exec "systemd-tpm2"; then
    echo "WARNING: TPM2 plugin not found" >&2
fi
```

### Runtime (Local-Top Execution)

Runtime unlock scripts (`initramfs/local-top/00-smartcard-root-tpm2`) have their own token detection and unlock logic. They do **not** source the shared libraries because:
- They execute in the initramfs root, not the build environment
- They require inline implementations (they cannot assume /usr is available)
- Token detection is straightforward enough to not require shared code

## Dracut Hooks Usage

### Module Installation (module-setup.sh)

The module declares dependencies and installs hooks at pre-mount stage:

```bash
check() {
    require_binaries cryptsetup || return 1
}

install() {
    inst_simple /usr/share/luks-root-smartcard/smartcard-common-lib.sh
    
    inst_hook pre-mount 01 "$moddir/smartcard-root-common.sh"
    inst_hook pre-mount 10 "$moddir/smartcard-root-token-detection.sh"
    inst_hook pre-mount 20 "$moddir/smartcard-root-tpm2.sh"
    # ... other hooks
}
```

### Build-Time (module-setup.sh Context)

Hooks are **not executed** during module installation. Instead, `module-setup.sh` specifies which binaries and libraries to include. Hooks are installed as-is into the initramfs.

### Runtime (Hook Execution in Initramfs)

Each runtime hook sources the shared library:

```sh
. /lib/smartcard-common-lib.sh
```

Then performs token detection and unlock attempts. Unlike initramfs-tools:
- No asset copying happens at runtime; all required binaries are pre-installed by dracut's module system
- Hooks can focus purely on unlock logic
- Configuration is loaded via `_load_inclusion_config`

## Key Differences Between Systems

| Aspect | Initramfs-Tools | Dracut |
|--------|---|---|
| **Hook Type** | Hooks declare asset inclusion & prerequisites | Modules declare dependencies; hooks install assets or run logic |
| **Build Time** | Hooks copy binaries/libs into initramfs | Module pre-installs via `inst` in module-setup.sh |
| **Copy Mechanism** | `copy_exec()`, `copy_file()` | `inst`, `inst_simple()`, `inst_multiple()` |
| **Config File** | `/etc/luks-root-smartcard/initramfs.conf` | Same; sourced at runtime |
| **Shared Library Location** | `/usr/share/luks-root-smartcard/` | `/lib/smartcard-common-lib.sh` (in initramfs) |
| **Hook Location** | `initramfs/hooks/` → runs at build time | `dracut/` → installed & run at boot |
| **Pre-Mount Stage** | `local-top/` (priority-ordered) | `pre-mount` hook stage |
| **Cleanup Stage** | `local-bottom/` | `cleanup` hook |

## Configuration

Both systems respect the same configuration file:

**`/etc/luks-root-smartcard/initramfs.conf`**

```sh
# Asset inclusion mode: "all" (default) or "detected"
# "all"      - include all smartcard workflows unconditionally
# "detected" - only include workflows with detected tokens
SMARTCARD_INITRAMFS_INCLUDE=detected

# GPG source keyring (optional)
SMARTCARD_GPG_SOURCE_HOME="/root/.gnupg"
SMARTCARD_GPG_SOURCE_USER="alice"
```

Environment variables override config file:

```sh
SMARTCARD_INITRAMFS_INCLUDE=all dracut -f
```

## Packaging and Installation

### For Initramfs-Tools

Install to:
- `/usr/share/initramfs-tools/hooks/smartcard-root-*` — Hook scripts
- `/usr/share/initramfs-tools/scripts/local-top/smartcard-root-*` — Runtime unlock scripts
- `/usr/share/initramfs-tools/scripts/local-bottom/smartcard-root` — Cleanup script
- `/usr/share/luks-root-smartcard/smartcard-common-lib.sh` — Shared library

### For Dracut

Install to:
- `/usr/lib/dracut/modules.d/90smartcard-root/module-setup.sh`
- `/usr/lib/dracut/modules.d/90smartcard-root/smartcard-root-*.sh`
- `/usr/share/luks-root-smartcard/smartcard-common-lib.sh` — Shared library

Update `debian/install` and Dracut module registration accordingly.

## Testing

### Verify Syntax

```sh
sh -n scripts/smartcard-common-lib.sh
sh -n scripts/smartcard-hook-common.sh
for hook in initramfs/hooks/smartcard-root-*; do sh -n "$hook"; done
for hook in dracut/smartcard-root-*.sh; do sh -n "$hook"; done
bash -n dracut/module-setup.sh
```

### Test Initramfs Hooks

```sh
sudo update-initramfs -u -k all
# Check for warnings during regeneration
# Verify realpath, plugins, and libraries in /boot/initrd.img-*
```

### Test Dracut Module

```sh
sudo dracut -f --add smartcard-root
# Check for module loading and asset installation
lsinitrd /boot/initramfs-*.img | grep smartcard
```

## Future Enhancements

1. **Unified Unlock Logic** — Extract boot-time token detection and unlock attempts into a shared script that both systems can invoke
2. **Configuration Standardization** — Create a common dracut.conf.d drop-in format
3. **Logging Harmonization** — Standardize debug output format across both systems
4. **Error Handling** — Unified fallback strategies when token unlock fails
