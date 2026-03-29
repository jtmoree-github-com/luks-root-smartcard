#!/bin/sh
set -eu

img=/boot/efi/EFI/Linux/linux-unsigned.efi
simg=/boot/efi/EFI/Linux/linux-signed.efi
simgold=/boot/efi/EFI/Linux/linux-signed-old.efi

kernel=${1:-}
initrd=${2:-}
key=${3:-}
cert=${4:-}

if [ -z "$kernel" ] || [ -z "$initrd" ]; then
	echo "usage: $0 <kernel> <initrd> [key cert]" >&2
	exit 1
fi

tmpdir=""
sign_key=""
sign_cert=""

cleanup() {
	[ -n "$tmpdir" ] && rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

# Keep signing material private to this process.
umask 077

if [ -z "$key" ] && [ -z "$cert" ]; then
	tmpdir="$(mktemp -d /tmp/uki.XXXXXX)"
	chmod 700 "$tmpdir"
	sign_key="$tmpdir/uki.key"
	sign_cert="$tmpdir/uki.crt"

	openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	  -keyout "$sign_key" -out "$sign_cert" \
	  -subj "/CN=My UKI Signing Key/" \
	  -addext "extendedKeyUsage=codeSigning"
	chmod 600 "$sign_key" "$sign_cert"
elif [ -z "$key" ] || [ -z "$cert" ]; then
	echo "error: key and cert must both be provided" >&2
	exit 1
else
	[ -f "$key" ] || { echo "error: key file not found: $key" >&2; exit 1; }
	[ -f "$cert" ] || { echo "error: cert file not found: $cert" >&2; exit 1; }
	sign_key="$key"
	sign_cert="$cert"
fi

ukify build --linux="$kernel" --initrd="$initrd" --cmdline="$(cat /proc/cmdline)" --output="$img"
if [ -f "$img" ] ; then
	if [ -f "$simg" ]; then
		mv -f "$simg" "$simgold"
	fi
	sbsign --key "$sign_key" --cert "$sign_cert" --output "$simg" "$img"
fi
