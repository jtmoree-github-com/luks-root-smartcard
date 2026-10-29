# Boot hardening options

The key security principles are the same across firmware types.  Often hardware issues make some of these impossible. The goal of this document is to mitigate risks as much as possible.

## Dual boot

If booting multiple systems it will limit options.  Booting MS Windows severely limits our options.

## Risks:

1. Unauthorized changes to BIOS/UEFI boot settings, firmware tampering
2. Booting from removable media to read/alter system and data
3. Disk extraction
4. Modifying a UEFI boot file
5. Modifying the post-UEFI/OS boot process
6. Reading the filesystem without the boot chain
7. Lockouts, failed unlocks, and loss of access during recovery or hardware failure
8. Stolen passphrases and software-key theft
9. Access to recovery resources e.g. backups of secrets and keys

## Principles:

| Principle | Protects against | Vulnerable to |
| --- | --- | --- |
| a. Password on firmware/admin access | 1 | 2,3,4,5,6,7,8 |
| b. Disable boot methods | 2 | 3,4,5,6,7,8 |
| c. Full Disk Encryption (all but EFI)^ | 2,3 | 4,7,8 |
| d. Encrypt the boot partition | 4,5 | 3,4,5,7,8 |
| e. Encrypt the root partition | 6 | 3,4,5,7,8 |
| f. TPM hardware-backed unlock^ | 3,4,5,8 | 1,2,3,4,5,6,7 |
| g. Keep a tested recovery path | 7 | 1,2,3,4,5,6,8 |
| h. Secure Boot | 4 | 1,2,3,5,6,7,8 |
| i. Secured backups | 9 | 1,2,3,4,5,6,7,8 |
| j. Unified Kernel Image (UKI) | 3,4,5,8 | 7 |
---
^There is a high probability that these features will not work for your system.

## Use Case: Maximum security

If we can use all of the principles it maximizes security.  We have protected our system from physical attacks and tampering via full disk encryption and  Secure boot.  Our data is also securely backed up and we have secure recovery options.  The key risks become theft of the secrets such as passphrases and recovery materials or a bricked system due to fragile NEW code that implements these security features.

## Use Case: No Full Disk Encryption and outdated TPM

This is likely our reality as almost no one has FDE+TPM working.  Most installers don't support it and those that do are often buggy to a fault.  When it does work it comes with tradeoffs such as multiple prompts on boot and lack of support for hardware such as tpm and smart cards.

The ideal would be to use Unified Kernal Images with secure boot.  UKI is the combination of the Linux kernel and the initial ram disk in a single binary  signed and checked by Secure Boot.   If we use UKI we can be assured that our boot process is safe.  If we have that assurance we can trust the prompts during boot.  If we want to reduce the prompt fatigue there are other options such as using smartcards.  Note that since the boot material sits on the unencrypted EFI we must take care NOT to store the decryption materials inside the UKI as an attacker with physical access could compromise the system.

Since the TPM support on linux is lacking it is likely that we cannot use TPM to protect our boot but we don't need it with UKI. Unfortunately, UKI seems to be fragile.  I bricked the first system where I tried to enable it.

## Use Case: No UKI

Most principles are still available to us even when we cannot use UKI and encrypt the entire drive.  We start with securing UEFI against tampering and alternative booting.  In addition, we encrypt the root partition and use Secure Boot to limit the boot process to the shim process used by most distros.

This situation is still vulnerable to physical access where an attacker removes the drive and modifies the boot process.  Since the shim does not validate the initrd (nor the kernel I think) we would not know if our system had been compromised.  Even if we modify the current process to sign our own kernel and initrd the attacker could modify boot to falsely report the signature checks.   

Some Linux vendors are working toward better security of the boot process.  Ubuntu 26.10 has support for FDE which is limited but a start in one direction.

# Resources

* https://sites.google.com/site/jtmoree/knowledge-base/harden-linux-security
* https://linuxsecurity.com/features/secure-boot-linux-explainer
* https://ubuntu.com/blog/what-is-system-hardening-definition-and-best-practices
