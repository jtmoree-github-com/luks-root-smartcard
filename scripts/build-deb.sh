#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

BUMP_MODE="${1:-}"

case "$BUMP_MODE" in
	"" )
		;;
	bump|--bump)
		# Increment patch version in debian/changelog when explicitly requested.
		CL="debian/changelog"
		cur="$(head -1 "$CL" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
		major="${cur%%.*}"
		rest="${cur#*.}"
		minor="${rest%%.*}"
		patch="${rest#*.}"
		patch=$(( patch + 1 ))
		new="${major}.${minor}.${patch}"
		sed -i "1s/($cur)/($new)/" "$CL"
		echo "Version: $cur -> $new"
		;;
	*)
		echo "Usage: $0 [bump|--bump]" >&2
		exit 2
		;;
esac

if [ -z "$BUMP_MODE" ]; then
	cur="$(head -1 debian/changelog | sed -n 's/.*(\([^)]*\)).*/\1/p')"
	echo "Version unchanged: $cur"
fi

echo "[1/2] Building package"
dpkg-buildpackage -us -uc -b

echo "[2/2] Artifacts"
ls -1 "$(dirname "$PROJECT_ROOT")"/luks-root-smartcard-tools_* || true
