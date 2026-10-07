# ax2: Debian 13 LUKS2 smartcard boot

Uses initramfs-tools and the **modified, working** luks-root-smartcard checkout.
Tested hardware: integrated SCM SCR 355 reader and card-a SmartCard-HSM,
RSA 2048 key/certificate `luks2-demo`, ID `04`.

## 1. Install Debian and dependencies

Install Debian 13 amd64 with encrypted LVM and a disk passphrase.
Keep that passphrase as the fallback.

```sh
sudo apt update
sudo apt install initramfs-tools cryptsetup cryptsetup-initramfs \
    systemd-cryptsetup opensc opensc-pkcs11 pcscd libccid libgcc-s1
sudo systemctl enable --now pcscd.socket
lsblk -o NAME,PATH,TYPE,FSTYPE,MOUNTPOINTS
cat /etc/crypttab
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so --list-token-slots
```

The commands below assume ax2's encrypted partition is `/dev/sda5`
and its mapping is `sda5_crypt`. Check these after each fresh installation;
the LUKS UUID changes.

## 2. Back up the header and enroll card-a

The existing RSA key and certificate on card-a can be reused.

```sh
sudo cryptsetup luksDump /dev/sda5   # Confirm Version: 2
sudo cryptsetup luksHeaderBackup /dev/sda5 \
    --header-backup-file /root/luks-header-before-smartcard.img
sudo systemd-cryptenroll \
    --pkcs11-token-uri='pkcs11:model=PKCS%2315%20emulated;manufacturer=www.CardContact.de;serial=DECC1800151;token=card-a;id=%04;object=luks2-demo;type=cert' \
    /dev/sda5
sudo systemd-cryptenroll /dev/sda5
```

Enrollment asks for the disk passphrase and card PIN. Confirm both a password
slot and a PKCS#11 slot remain. Store a protected header backup off the machine.

## 3. Install the working boot support

Run on **ax2**, from your modified checkout. A clean upstream clone does not
include our fixes or the additional `smartcard-libgcc` hook.

```sh
cd ~/laboratory/luks-root-smartcard
sudo install -d /etc/initramfs-tools/hooks \
    /etc/initramfs-tools/scripts/local-top \
    /etc/initramfs-tools/scripts/local-bottom
sudo install -m 0755 initramfs/hooks/smartcard-root-pkcs11 \
    initramfs/hooks/smartcard-libgcc /etc/initramfs-tools/hooks/
sudo install -m 0755 initramfs/local-top/10-smartcard-root-pkcs11 \
    /etc/initramfs-tools/scripts/local-top/
sudo install -m 0755 initramfs/local-bottom/smartcard-root \
    /etc/initramfs-tools/scripts/local-bottom/
```

In the installed local-top script, keep:

```sh
mapping="$(resolve_mapping "sda5_crypt")"
```

`sda5_crypt` must match the first field in `/etc/crypttab`, not the root LV name
or UUID. Keep the explicit OpenSC module path in all three `pkcs11-tool` calls.
Leave the normal Debian `/etc/crypttab` entry in place; this route does not
require `pkcs11-uri=auto` or dracut.

## 4. Build and test the normal initramfs

```sh
sudo cp -a "/boot/initrd.img-$(uname -r)" \
    "/boot/initrd.img-$(uname -r).before-smartcard"
sudo update-initramfs -u -k "$(uname -r)"
sudo update-grub
sudo lsinitramfs "/boot/initrd.img-$(uname -r)" | \
    grep -E '10-smartcard-root-pkcs11|local-bottom/smartcard-root|pkcs11-tool|libgcc_s'
```

Reboot using the normal Debian entry with the card inserted: enter its PIN.
Also test a cold boot and a boot without the card to verify passphrase fallback.
Keep the disk password slot and a recovery boot option.

## Kernel updates

Debian's normal kernel updates regenerate initramfs using the installed files
under `/etc/initramfs-tools/`. No new enrollment is needed: it stays in the
LUKS header. Boot the normal Debian entries generated for each kernel.

The old isolated `/root/ax2-smartcard-initramfs` configuration and manually
named `*-smartcard-initramfs` image are not automatically updated.
After changing repository scripts, reinstall them and rebuild the initramfs.
The current mapping and library path are specific to this amd64 configuration.
