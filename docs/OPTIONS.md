# Boot hardening options

The key security principles are the same across firmware types.  Often hardware issues make some of these impossible. The goal of this document is to mitigate risks as much as possible.

## Dual boot

If booting multiple systems it will limit options.  Booting MS Windows severely limits our options.

## Risks:

1. Unauthorized changes to BIOS/UEFI boot settings
2. Booting from removable media to read/alter system and data
3. Disk extraction
4. Modifying a UEFI registered boot file
5. Modifying post-UEFI (OS boot process)
6. Reading the filesystem without the boot chain
7. Lockouts, failed unlocks, and loss of access during recovery or hardware failure
8. Stolen passphrases and software-key theft
9. Access to recovery resources e.g. backups of secrets and keys
10. Theft of hardware to increase attack vectors
11. Hardware modification, firmware tampering

## Principles:

| Principle | Mitigates | Vulnerable to |
| --- | --- | --- |
| a. Password on firmware/admin access | 1 | 2,3,4,5,6,7,8,10,11 |
| b. Disable boot methods | 2 | 3,4,5,6,7,8,10,11 |
| c. Full Disk Encryption (all but EFI) | 2,3,10 | 4,7,8,11 |
| d. Encrypt the boot partition | 4,5,10 | 3,4,5,7,8,11 |
| e. Encrypt the root partition | 6,10 | 3,4,5,7,8,11 |
| f. TPM hardware-backed unlock | 3,4,5,8,10 | 1,2,3,4,5,6,7,11 |
| g. Keep a tested recovery path | 7 | 1,2,3,4,5,6,8,10,11 |
| h. Secure Boot | 4 | 1,2,3,5,6,7,8,10,11 |
| i. Secured backups | 9,10 | 1,2,3,4,5,6,7,8,11 |
| j. Unified Kernel Image (UKI) | 3,4,5,8 | 7,10,11 |
| k. Boot from Secure USB | 2,3,4,5,6,8 | 10,11 |
---

If we can use all of the principles it maximizes security.  We have protected our system from physical attacks and tampering via full disk encryption and  Secure boot.  Our data is also securely backed up and we have secure recovery options.  The key risks become theft of the secrets such as passphrases and recovery materials via hardware tampering, etc or a bricked system due to fragile NEW code that implements these security features.

## Use Case **Paradise**: Secure Boot+UKI

The ideal would be to use Unified Kernal Images (UKI) with secure boot.  UKI is the combination of the Linux kernel and the initial ram disk in a single binary signed and checked by Secure Boot.   If we use UKI+Secure Boot we can be assured that our boot process is safe.  If we have that assurance we can trust the prompts during boot.  If we want to reduce the prompt fatigue there are other options to assist.  *Note* that since the boot material sits on the unencrypted EFI we must take care NOT to store the decryption materials inside the UKI as an attacker with physical access could compromise the system.

Once UKI is booting the system from the efi partition we may encrypt the /boot partition to achieve Full Disk Encryption.  A handful of distros are supporting or have communities working on UKI solutions.  Almost no one has Full Disk Encryption working.  The systemd tpm implementation fails in boot even if set up works.  Most installers don't support these and those that do are buggy to a fault.  When it does work it comes with tradeoffs such as multiple prompts on boot and lack of support for other features.

Since the TPM support on linux is lacking it is likely that we cannot use TPM to protect our boot but we don't need it to protect Secure Boot UKI.  Unfortunately, both TPM support and UKI are fragile.  I trashed systems the first dozen times I tried to sign UKI and secure boot.  In some cases the systems were so badly trashed I had to reset to factory defaults.

## Use Case **Atlantis**: Full Disk Encryption+USB boot

If we encrypt the entire drive and boot from a secured usb drive there is no boot chain on the system to secure.   "Securing" a USB drive is arguably difficult but not impossible.  Using a hardened drive that is weatherproof, etc.  we could even shower with it.

We don't have to be overly concerned with securing UEFI settings on the system as we are going to boot our own media.  We don't have to encrypt the drive at all if our boot media contains a full OS.  At minimum we only need to store the kernel and initrd or a UKI.  A few communities are working on this approach but less than the other approaches.

## Use Case **Arcadia**: No UKI, No USB, Secure Boot+Shim

Given the barriers to hardening past this point, lack of awareness, and low risk of being compromised, this is the reality most users will live with.

Most hardening principles are still available to the majority of us even when we cannot use UKI and/or encrypt the entire drive.  Like with the aforementioned, we start with securing UEFI against tampering and alternative booting.  Again, we encrypt the root partition and use Secure Boot to limit the boot process to the Secure Boot shim process used by most Linux distros.  The installer probably sets up machine owner keys for us to assist with hardening boot.

This situation is still vulnerable to physical access where an attacker removes the drive and modifies the boot process.  Since the shim based verification only validates the kernel and not the initrd we would not know if our system had been compromised.  Even if we modify the current boot chain to sign our own kernel and initrd the attacker could modify boot process in the initrd to falsely report the signature checks.

# Resources

* https://sites.google.com/site/jtmoree/knowledge-base/harden-linux-security
* https://linuxsecurity.com/features/secure-boot-linux-explainer
* https://ubuntu.com/blog/what-is-system-hardening-definition-and-best-practices
