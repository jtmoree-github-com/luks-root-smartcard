#!/bin/sh
# dracut hook: smartcard-root-cleanup
# Cleanup smartcard daemons and runtime state after unlock

# Kill GPG daemons if started
if [ -x /usr/bin/gpgconf ] && [ -d "/run/cryptroot/gnupghome" ]; then
    gpgconf --homedir="/run/cryptroot/gnupghome" --kill all 2>/dev/null || true
fi

# Kill lingering smartcard-related daemons
for _daemon in scdaemon gpg-agent pkcs11-tool pcscd; do
    if pidof "$_daemon" >/dev/null 2>&1; then
        killall -TERM "$_daemon" 2>/dev/null || true
    fi
done

# Clean up runtime state
rm -f /run/pcscd.pid /run/pcscd/pcscd.comm /run/smartcard-*

return 0
