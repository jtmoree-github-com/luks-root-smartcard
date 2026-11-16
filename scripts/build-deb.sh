#!/usr/bin/env bash
set -euo pipefail

msg() { echo "build-deb: $*" >&2; }
die() { echo "build-deb: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

usage() {
  cat <<'USAGE'
Usage: build-deb.sh [OPTIONS]

Build a Debian package for luks-root-smartcard-tools.

Options:
  --install         Install the built DEB after building
  --help            Show this help
USAGE
}

require_cmd dpkg-buildpackage
require_cmd git

REPO_ROOT="$(git rev-parse --show-toplevel)" || die "not in a git repository"
cd "$REPO_ROOT"

DO_INSTALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

msg "building Debian package..."
dpkg-buildpackage -us -uc

msg "done"

if [ "$DO_INSTALL" -eq 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    die "--install requires root"
  fi
  msg "installing packages..."
  apt install -y ../*.deb || die "installation failed"
fi
