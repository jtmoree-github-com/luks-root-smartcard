#!/usr/bin/env bash
set -euo pipefail

msg() { echo "build-rpm: $*" >&2; }
die() { echo "build-rpm: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

usage() {
  cat <<'EOF'
Usage: build-rpm.sh [OPTIONS]

Build an RPM package for luks-root-smartcard-tools.

Options:
  --output DIR      Output directory for built RPM (default: from config or ./rpmbuild-output)
  --spec FILE       Path to spec file (default: ./luks-root-smartcard-tools.spec)
  --install         Install the built RPM after building
  --help            Show this help

Configuration file: ~/.config/luks-root-smartcard/ppa.env
  Sets: LUKS_BUILD_OUTPUT_DIR
EOF
}

# Load config
CONFIG_FILE="$HOME/.config/luks-root-smartcard/ppa.env"
OUTPUT_DIR=""
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  OUTPUT_DIR="${LUKS_BUILD_OUTPUT_DIR:-}"
fi

# Defaults
OUTPUT_DIR="${OUTPUT_DIR:-.}/rpmbuild-output"
SPEC_FILE="./luks-root-smartcard-tools.spec"
DO_INSTALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --spec) SPEC_FILE="$2"; shift 2 ;;
    --install) DO_INSTALL=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_cmd rpmbuild
require_cmd tar
require_cmd git

REPO_ROOT="$(git rev-parse --show-toplevel)" || die "not in a git repository"
cd "$REPO_ROOT"

[ -f "$SPEC_FILE" ] || die "spec file not found: $SPEC_FILE"

SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"

msg "repository root: $REPO_ROOT"
msg "spec file: $SPEC_FILE"

# Extract version from spec file
VERSION="$(grep '^Version:' "$SPEC_FILE" | awk '{print $2}')" || die "could not extract version from spec"
msg "building version: $VERSION"

# Create build directory structure
BUILD_DIR="$(mktemp -d)"
trap "rm -rf '$BUILD_DIR'" EXIT

SOURCES_DIR="$BUILD_DIR/SOURCES"
SPECS_DIR="$BUILD_DIR/SPECS"
BUILD_SUBDIR="$BUILD_DIR/BUILD"
RPMS_DIR="$BUILD_DIR/RPMS"
SRPMS_DIR="$BUILD_DIR/SRPMS"

mkdir -p "$SOURCES_DIR" "$SPECS_DIR" "$BUILD_SUBDIR" "$RPMS_DIR" "$SRPMS_DIR"

msg "build directory: $BUILD_DIR"

# Create source tarball
ARCHIVE_NAME="luks-root-smartcard-$VERSION"
ARCHIVE_PATH="$SOURCES_DIR/$ARCHIVE_NAME.tar.gz"

msg "creating source tarball: $ARCHIVE_NAME.tar.gz"
git archive --format=tar.gz --prefix="$ARCHIVE_NAME/" \
  --output="$ARCHIVE_PATH" HEAD

msg "copied spec file to $SPECS_DIR"
cp "$SPEC_FILE" "$SPECS_DIR/"

msg "building RPM..."
rpmbuild \
  --define "_topdir $BUILD_DIR" \
  -ba "$SPECS_DIR/$(basename "$SPEC_FILE")"

msg "build complete"

# Copy outputs to output directory
mkdir -p "$OUTPUT_DIR"
msg "copying artifacts to $OUTPUT_DIR"

cp "$RPMS_DIR"/**/*.rpm "$OUTPUT_DIR/" 2>/dev/null || true
cp "$SRPMS_DIR"/*.src.rpm "$OUTPUT_DIR/" 2>/dev/null || true

if [ "$(ls -1 "$OUTPUT_DIR"/*.rpm 2>/dev/null | wc -l)" -eq 0 ]; then
  die "no RPMs found after build"
fi

msg "packages built:"
ls -lh "$OUTPUT_DIR"/*.rpm

if [ "$DO_INSTALL" -eq 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    die "--install requires root; run with sudo or manually install with: sudo dnf install $OUTPUT_DIR/*.rpm"
  fi
  msg "installing built packages..."
  dnf install -y "$OUTPUT_DIR"/*.rpm || die "installation failed"
  msg "installation complete"
else
  msg "to install, run: sudo dnf install $OUTPUT_DIR/*.rpm"
fi

msg "done"
