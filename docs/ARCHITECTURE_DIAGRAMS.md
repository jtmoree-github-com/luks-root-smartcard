# Code Architecture Diagrams (Mermaid)

## System Overview

```mermaid
graph TB
    subgraph shared["Shared Core Library (smartcard-common-lib.sh)"]
        direction LR
        devres["Device Resolution<br/>_resolve_dev_hook()"]
        tokdet["Token Detection<br/>_has_token()<br/>_has_systemd_*_token()"]
        config["Configuration<br/>_load_inclusion_config()<br/>_should_include_token_assets()"]
        cryptscan["Crypttab Scanning<br/>_uses_token_type()"]
        pluginhandl["Plugin Handling<br/>_copy_cryptsetup_plugin()<br/>_copy_ldd_deps()"]
        utils["Utilities<br/>_find_binary_path()"]
        gpghelp["GPG Helpers<br/>_resolve_gpg_source_homedir()<br/>_import_user_keyring_pubkeys()"]
        
        devres --> tokdet
        tokdet --> config
        config --> cryptscan
        cryptscan --> pluginhandl
        pluginhandl --> utils
        utils --> gpghelp
    end
    
    subgraph initadapter["Initramfs Adapter<br/>(smartcard-hook-common.sh)"]
        adaptwrap["copy_exec Wrappers<br/>_initramfs_copy()<br/>_copy_exec_with_deps()"]
        dirutil["Directory/File Utilities<br/>_copy_dir_tree()<br/>_copy_file_maybe()"]
        integhelp["Integration Helpers<br/>_should_include_assets()"]
        
        adaptwrap --> dirutil
        dirutil --> integhelp
    end
    
    subgraph initbuild["Initramfs Build Hooks<br/>(5 Hooks)"]
        icommon["smartcard-root-common"]
        itpm2["smartcard-root-tpm2"]
        ifido2["smartcard-root-fido2"]
        ipkcs11["smartcard-root-pkcs11"]
        igpg["smartcard-root-gpg"]
    end
    
    subgraph dracut["Dracut Runtime Hooks<br/>(7 Hooks)"]
        dmodsetup["module-setup.sh"]
        dcommon["smartcard-root-common"]
        ddetect["smartcard-root-token-detection"]
        dtpm2["smartcard-root-tpm2"]
        dfido2["smartcard-root-fido2"]
        dpkcs11["smartcard-root-pkcs11"]
        dgpg["smartcard-root-gpg"]
        dcleanup["smartcard-root-cleanup"]
    end
    
    shared --> initadapter
    shared --> initbuild
    shared --> dracut
    
    initadapter --> initbuild
    
    style shared fill:#4CAF50,color:#fff
    style initadapter fill:#2196F3,color:#fff
    style initbuild fill:#FF9800,color:#fff
    style dracut fill:#9C27B0,color:#fff
```

## Initramfs-Tools Build Time Flow

```mermaid
graph TD
    build["update-initramfs -u"] --> hook1["initramfs/hooks/smartcard-root-common"]
    build --> hook2["initramfs/hooks/smartcard-root-tpm2"]
    build --> hook3["initramfs/hooks/smartcard-root-fido2"]
    build --> hook4["initramfs/hooks/smartcard-root-pkcs11"]
    build --> hook5["initramfs/hooks/smartcard-root-gpg"]
    
    hook1 --> source1["Source hook-functions"]
    hook1 --> source2["Source smartcard-common-lib.sh"]
    source2 --> copy1["copy_exec realpath"]
    
    hook2 --> source3["Source hook-functions<br/>Source smartcard-common-lib.sh"]
    source3 --> load2["_load_inclusion_config"]
    load2 --> uses2["_uses_token_type systemd-tpm2"]
    uses2 --> copy2["_copy_cryptsetup_plugin"]
    copy2 --> copydep2["_copy_ldd_deps"]
    
    hook3 --> source4["Source hook-functions<br/>Source smartcard-common-lib.sh"]
    source4 --> load3["_load_inclusion_config"]
    load3 --> uses3["_uses_token_type systemd-fido2"]
    uses3 --> copy3["_copy_cryptsetup_plugin"]
    copy3 --> copydep3["_copy_ldd_deps"]
    
    hook4 --> source5["Source hook-functions<br/>Source smartcard-common-lib.sh"]
    source5 --> load4["_load_inclusion_config"]
    load4 --> uses4["_uses_token_type systemd-pkcs11"]
    uses4 --> copy4["_copy_cryptsetup_plugin"]
    copy4 --> copydep4["_copy_ldd_deps"]
    
    hook5 --> source6["Source hook-functions<br/>Source smartcard-common-lib.sh"]
    source6 --> load5["_load_inclusion_config"]
    load5 --> uses5["_uses_token_type gpg-token"]
    uses5 --> copy5["Copy GPG assets"]
    copy5 --> copydep5["_copy_cryptsetup_plugin"]
    
    copydep2 --> initrd["Generate /boot/initrd.img"]
    copydep3 --> initrd
    copydep4 --> initrd
    copydep5 --> initrd
    copy1 --> initrd
    
    style hook1 fill:#FF9800
    style hook2 fill:#FF9800
    style hook3 fill:#FF9800
    style hook4 fill:#FF9800
    style hook5 fill:#FF9800
    style initrd fill:#4CAF50,color:#fff
```

## Initramfs-Tools Boot Time Flow

```mermaid
graph TD
    boot["Kernel Boot with initramfs"] --> local_top["Local-Top Stage"]
    
    local_top --> tpm2_boot["00-smartcard-root-tpm2"]
    tpm2_boot --> tpm2_det["Auto-detect TPM2 token"]
    tpm2_det --> tpm2_wait["Wait for TPM device"]
    tpm2_wait --> tpm2_unlock["cryptsetup luksOpen --token-type systemd-tpm2"]
    tpm2_unlock --> tpm2_check{"Token unlock<br/>successful?"}
    
    tpm2_check -->|Yes| skip_fido["Skip FIDO2/PKCS11"]
    tpm2_check -->|No| fido2_boot["05-smartcard-root-fido2<br/>(if tpm2 failed)"]
    
    skip_fido --> root_mounted["Root device mounted"]
    fido2_boot --> fido2_det["Auto-detect FIDO2 token"]
    fido2_det --> fido2_unlock["cryptsetup luksOpen --token-type systemd-fido2"]
    fido2_unlock --> fido2_check{"FIDO2 unlock<br/>successful?"}
    
    fido2_check -->|Yes| skip_pkcs11["Skip PKCS11"]
    fido2_check -->|No| pkcs11_boot["10-smartcard-root-pkcs11"]
    
    skip_pkcs11 --> root_mounted
    pkcs11_boot --> pkcs11_det["Auto-detect PKCS11 token"]
    pkcs11_det --> pkcs11_unlock["cryptsetup luksOpen --token-type systemd-pkcs11"]
    pkcs11_unlock --> pkcs11_check{"PKCS11 unlock<br/>successful?"}
    
    pkcs11_check -->|Yes| skip_gpg["Skip GPG"]
    pkcs11_check -->|No| gpg_boot["20-smartcard-root-gpg"]
    
    skip_gpg --> root_mounted
    gpg_boot --> gpg_det["Auto-detect GPG token"]
    gpg_det --> gpg_unlock["Attempt GPG unlock"]
    gpg_unlock --> gpg_check{"GPG unlock<br/>successful?"}
    
    gpg_check -->|Yes| root_mounted
    gpg_check -->|No| fallback["Fall back to standard cryptroot"]
    
    fallback --> root_mounted
    root_mounted --> local_bottom["Local-Bottom Stage"]
    local_bottom --> cleanup["smartcard-root cleanup"]
    cleanup --> killgpg["Kill GPG daemons"]
    killgpg --> killpcscd["Kill pcscd"]
    killpcscd --> boot_complete["Boot continues"]
    
    style tpm2_boot fill:#FF9800
    style fido2_boot fill:#FF9800
    style pkcs11_boot fill:#FF9800
    style gpg_boot fill:#FF9800
    style cleanup fill:#FF9800
    style boot_complete fill:#4CAF50,color:#fff
    style root_mounted fill:#4CAF50,color:#fff
```

## Dracut Module Installation Flow

```mermaid
graph TD
    dracut_cmd["dracut -f --add smartcard-root"] --> check["check()"]
    check --> require_crypto["require_binaries cryptsetup"]
    require_crypto --> depends["depends()"]
    depends --> return_crypt["return: crypt"]
    
    return_crypt --> install["install()"]
    install --> inst_lib["inst_simple smartcard-common-lib.sh"]
    inst_lib --> hook1["inst_hook pre-mount 01<br/>smartcard-root-common.sh"]
    hook1 --> hook2["inst_hook pre-mount 10<br/>smartcard-root-token-detection.sh"]
    hook2 --> hook3["inst_hook pre-mount 20<br/>smartcard-root-tpm2.sh"]
    hook3 --> hook4["inst_hook pre-mount 21<br/>smartcard-root-fido2.sh"]
    hook4 --> hook5["inst_hook pre-mount 22<br/>smartcard-root-pkcs11.sh"]
    hook5 --> hook6["inst_hook pre-mount 23<br/>smartcard-root-gpg.sh"]
    hook6 --> hook7["inst_hook cleanup 99<br/>smartcard-root-cleanup.sh"]
    
    hook7 --> installkernel["installkernel()"]
    installkernel --> mods["instmods tpm, tpm_tis, tpm_crb<br/>instmods hid, hid_generic, hidraw"]
    
    mods --> initramfs["Generate /boot/initramfs-*.img"]
    initramfs --> done["Module ready for boot"]
    
    style check fill:#2196F3,color:#fff
    style install fill:#2196F3,color:#fff
    style installkernel fill:#2196F3,color:#fff
    style done fill:#4CAF50,color:#fff
```

## Dracut Boot Time Flow

```mermaid
graph TD
    boot["Kernel Boot"] --> pre_mount["Pre-Mount Stage"]
    
    pre_mount --> common["01-smartcard-root-common"]
    common --> detect["10-smartcard-root-token-detection"]
    detect --> load_config["_load_inclusion_config"]
    load_config --> resolve["_resolve_dev_hook"]
    resolve --> scan1["_has_token TPM2"]
    scan1 --> exp1["export SMARTCARD_HAS_TPM2_TOKEN=1<br/>if found"]
    
    exp1 --> scan2["_has_token FIDO2"]
    scan2 --> exp2["export SMARTCARD_HAS_FIDO2_TOKEN=1<br/>if found"]
    
    exp2 --> scan3["_has_token PKCS11"]
    scan3 --> exp3["export SMARTCARD_HAS_PKCS11_TOKEN=1<br/>if found"]
    
    exp3 --> scan4["_has_token GPG"]
    scan4 --> exp4["export SMARTCARD_HAS_GPG_TOKEN=1<br/>if found"]
    
    exp4 --> tpm2_hook["20-smartcard-root-tpm2"]
    tpm2_hook --> tpm2_check{"SMARTCARD_HAS<br/>_TPM2_TOKEN=1?"}
    tpm2_check -->|No| fido2_hook["21-smartcard-root-fido2"]
    tpm2_check -->|Yes| tpm2_wait["wait_for_tpm_device"]
    tpm2_wait --> tpm2_open["cryptsetup luksOpen<br/>--token-type systemd-tpm2"]
    tpm2_open --> tpm2_result{"Success?"}
    tpm2_result -->|Yes| mounted["Root mounted"]
    tpm2_result -->|No| fido2_hook
    
    fido2_hook --> fido2_check{"SMARTCARD_HAS<br/>_FIDO2_TOKEN=1?"}
    fido2_check -->|No| pkcs11_hook["22-smartcard-root-pkcs11"]
    fido2_check -->|Yes| fido2_open["cryptsetup luksOpen<br/>--token-type systemd-fido2"]
    fido2_open --> fido2_result{"Success?"}
    fido2_result -->|Yes| mounted
    fido2_result -->|No| pkcs11_hook
    
    pkcs11_hook --> pkcs11_check{"SMARTCARD_HAS<br/>_PKCS11_TOKEN=1?"}
    pkcs11_check -->|No| gpg_hook["23-smartcard-root-gpg"]
    pkcs11_check -->|Yes| pkcs11_open["cryptsetup luksOpen<br/>--token-type systemd-pkcs11"]
    pkcs11_open --> pkcs11_result{"Success?"}
    pkcs11_result -->|Yes| mounted
    pkcs11_result -->|No| gpg_hook
    
    gpg_hook --> gpg_check{"SMARTCARD_HAS<br/>_GPG_TOKEN=1?"}
    gpg_check -->|No| cleanup_stage["Cleanup Stage"]
    gpg_check -->|Yes| gpg_open["cryptsetup luksOpen<br/>--token-type gpg-token"]
    gpg_open --> gpg_result{"Success?"}
    gpg_result -->|Yes| mounted
    gpg_result -->|No| cleanup_stage
    
    mounted --> cleanup_stage
    cleanup_stage --> cleanup_hook["99-smartcard-root-cleanup"]
    cleanup_hook --> killgpg["killall gpg-agent scdaemon"]
    killgpg --> killpcscd["killall pcscd"]
    killpcscd --> boot_done["Boot continues to real root"]
    
    style detect fill:#9C27B0,color:#fff
    style tpm2_hook fill:#9C27B0,color:#fff
    style fido2_hook fill:#9C27B0,color:#fff
    style pkcs11_hook fill:#9C27B0,color:#fff
    style gpg_hook fill:#9C27B0,color:#fff
    style cleanup_hook fill:#9C27B0,color:#fff
    style mounted fill:#4CAF50,color:#fff
    style boot_done fill:#4CAF50,color:#fff
```

## Token Detection Hierarchy

```mermaid
graph TB
    root["LUKS2 Root Device<br/>(cryptsetup token export)"]
    
    root --> scan["Scan Token IDs 0-31"]
    
    scan --> tok0["Token 0<br/>Type?"]
    scan --> tok1["Token 1<br/>Type?"]
    scan --> tok2["Token 2<br/>Type?"]
    scan --> tokN["Token N<br/>Type?"]
    
    tok0 -->|systemd-tpm2| tpm2["TPM2 Unlock<br/>Attempt"]
    tok0 -->|systemd-fido2| fido2["FIDO2 Unlock<br/>Attempt"]
    tok0 -->|systemd-pkcs11| pkcs11["PKCS#11 Unlock<br/>Attempt"]
    tok0 -->|gpg-token| gpg["GPG Unlock<br/>Attempt"]
    tok0 -->|other/none| skip0["Skip"]
    
    tok1 -->|systemd-tpm2| tpm2
    tok1 -->|systemd-fido2| fido2
    tok1 -->|systemd-pkcs11| pkcs11
    tok1 -->|gpg-token| gpg
    tok1 -->|other/none| skip1["Skip"]
    
    tok2 -->|systemd-tpm2| tpm2
    tok2 -->|systemd-fido2| fido2
    tok2 -->|systemd-pkcs11| pkcs11
    tok2 -->|gpg-token| gpg
    tok2 -->|other/none| skip2["Skip"]
    
    tokN -->|systemd-tpm2| tpm2
    tokN -->|systemd-fido2| fido2
    tokN -->|systemd-pkcs11| pkcs11
    tokN -->|gpg-token| gpg
    tokN -->|other/none| skipN["Skip"]
    
    tpm2 --> hierarchy["Priority Order<br/>1. systemd-tpm2 (attempted first)<br/>2. systemd-fido2<br/>3. systemd-pkcs11<br/>4. gpg-token<br/>(stop at first success)"]
    fido2 --> hierarchy
    pkcs11 --> hierarchy
    gpg --> hierarchy
    
    hierarchy --> fallback["If all fail:<br/>Fall back to<br/>standard cryptroot<br/>password prompt"]
    
    style root fill:#2196F3,color:#fff
    style tpm2 fill:#4CAF50,color:#fff
    style fido2 fill:#FF9800,color:#fff
    style pkcs11 fill:#9C27B0,color:#fff
    style gpg fill:#E91E63,color:#fff
    style fallback fill:#f44336,color:#fff
```

## Code Reuse Across Systems

```mermaid
graph LR
    subgraph shared["Shared Library Functions<br/>(smartcard-common-lib.sh)"]
        direction TB
        resolve["_resolve_dev_hook"]
        hastoken["_has_token"]
        hasspec["_has_systemd_tpm2_token<br/>_has_systemd_fido2_token<br/>_has_systemd_pkcs11_token<br/>_has_gpg_token"]
        uses["_uses_token_type"]
        loadconf["_load_inclusion_config"]
        shouldinc["_should_include_token_assets"]
        copyplugin["_copy_cryptsetup_plugin"]
        copyldd["_copy_ldd_deps"]
        findbin["_find_binary_path"]
        gpgresolve["_resolve_gpg_source_homedir"]
        gpgimport["_import_user_keyring_pubkeys_into_initramfs"]
        
        resolve --> hastoken
        hastoken --> hasspec
        hasspec --> uses
        uses --> loadconf
        loadconf --> shouldinc
        shouldinc --> copyplugin
        copyplugin --> copyldd
        copyldd --> findbin
        findbin --> gpgresolve
        gpgresolve --> gpgimport
    end
    
    subgraph initramfs["Initramfs-Tools<br/>(5 Hooks × 2 contexts)"]
        direction TB
        ihooks["smartcard-root-tpm2<br/>smartcard-root-fido2<br/>smartcard-root-pkcs11<br/>smartcard-root-gpg<br/>smartcard-root-common"]
        iuse["Uses:<br/>_load_inclusion_config<br/>_uses_token_type<br/>_copy_cryptsetup_plugin<br/>_copy_ldd_deps<br/>_find_binary_path<br/>_resolve_gpg_source_homedir<br/>_import_user_keyring"]
        ihooks --> iuse
    end
    
    subgraph dracut["Dracut<br/>(7 Hooks)"]
        direction TB
        dhooks["smartcard-root-token-detection<br/>smartcard-root-tpm2<br/>smartcard-root-fido2<br/>smartcard-root-pkcs11<br/>smartcard-root-gpg<br/>smartcard-root-cleanup"]
        duse["Uses:<br/>_load_inclusion_config<br/>_resolve_dev_hook<br/>_has_token<br/>_should_include_token_assets"]
        dhooks --> duse
    end
    
    shared -.->|consumed by| initramfs
    shared -.->|consumed by| dracut
    
    style shared fill:#4CAF50,color:#fff,stroke:#2e7d32,stroke-width:3px
    style initramfs fill:#FF9800,color:#fff
    style dracut fill:#9C27B0,color:#fff
```

## Dependency Graph

```mermaid
graph LR
    subgraph build["Build Time (initramfs-tools)"]
        ihooks["initramfs/hooks/<br/>smartcard-root-*"]
        icommon["smartcard-common-lib.sh"]
        ihooks -->|sources| icommon
    end
    
    subgraph buildDracut["Build Time (dracut)"]
        modulesetup["dracut/module-setup.sh"]
        modulesetup -->|inst_simple| icommon
    end
    
    subgraph runtimeInit["Runtime (initramfs)"]
        localtop["scripts/local-top/<br/>00-smartcard-root-tpm2"]
        localbottom["scripts/local-bottom/<br/>smartcard-root"]
        localtop -->|inline impl.| skip1["(no shared lib)"]
        localbottom -->|inline impl.| skip2["(no shared lib)"]
    end
    
    subgraph runtimeDracut["Runtime (dracut)"]
        dracs["dracut/smartcard-root-*.sh<br/>(7 hooks)"]
        dracommon["smartcard-common-lib.sh<br/>(installed in /lib)"]
        dracs -->|sources| dracommon
    end
    
    icommon -.->|same file| icommon
    
    style icommon fill:#4CAF50,color:#fff,stroke:#2e7d32,stroke-width:3px
    style ihooks fill:#FF9800,color:#fff
    style modulesetup fill:#2196F3,color:#fff
    style dracs fill:#9C27B0,color:#fff
    style skip1 fill:#ccc,color:#666
    style skip2 fill:#ccc,color:#666
```

## Shared vs Adapter-Specific Code

```mermaid
graph TB
    subgraph shared["Shared Library (smartcard-common-lib.sh)"]
        direction TB
        devres["Device Resolution<br/>Token Detection<br/>Configuration Loading<br/>Crypttab Scanning<br/>Plugin Discovery & Copying<br/>Dependency Resolution<br/>GPG Keyring Import"]
        inject["Adapter Injection<br/>_copy_ldd_deps &lt;copy_func&gt;<br/>_copy_cryptsetup_plugin &lt;copy_func&gt;"]
        devres --> inject
    end
    
    subgraph init["Initramfs (smartcard-hook-common.sh)"]
        direction TB
        initmods["Adapter Wrappers:<br/>_initramfs_copy()<br/>_copy_exec_with_deps()<br/>_copy_file_maybe()"]
    end
    
    subgraph dracut["Dracut (module-setup.sh)"]
        direction TB
        dracmod["Adapter Functions:<br/>inst_simple()<br/>inst_hook()<br/>inst_multiple()"]
    end
    
    shared -->|injects copy_func| init
    shared -->|injects copy_func| dracut
    
    style shared fill:#4CAF50,color:#fff,stroke:#2e7d32,stroke-width:3px
    style init fill:#2196F3,color:#fff
    style dracut fill:#9C27B0,color:#fff
```
