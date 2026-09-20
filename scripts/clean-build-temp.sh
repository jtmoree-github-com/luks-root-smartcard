#!/usr/bin/env bash
set -euo pipefail

repo="${1:-$PWD}"
cd "$repo"

echo "Cleaning temporary build artifacts in: $repo"

# Remove Debian packaging temp/build state.
rm -rf \
  debian/.debhelper \
  debian/luks-root-smartcard-tools \
  debian/tmp \
  debian/files \
  debian/*.debhelper.log \
  debian/*.substvars

# Remove common package build outputs from parent dir.
pkg_parent="$(dirname "$repo")"
rm -f \
  "$pkg_parent"/luks-root-smartcard-tools_*.deb \
  "$pkg_parent"/luks-root-smartcard-tools_*.build \
  "$pkg_parent"/luks-root-smartcard-tools_*.buildinfo \
  "$pkg_parent"/luks-root-smartcard-tools_*.changes \
  "$pkg_parent"/luks-root-smartcard-tools_*.dsc \
  "$pkg_parent"/luks-root-smartcard-tools_*.tar.* \
  "$pkg_parent"/luks-root-smartcard-tools_*.debian.tar.*

# Remove stale test temp dirs older than 30 minutes.
find /tmp -maxdepth 1 -type d \( -name 'tmp.*' -o -name 'test-pkcs11.*' -o -name 'test-luks.*' \) \
  -mmin +30 -print -exec rm -rf {} +

echo "Cleanup complete."
