#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/luks-root-smartcard/ppa.env"
DEFAULT_OUTPUT_DIR="$(dirname "$PROJECT_ROOT")"
BUILD_OUTPUT_DIR="${LUKS_BUILD_OUTPUT_DIR:-}"

cd "$PROJECT_ROOT"

BUMP_MODE=""
BUILD_MODE="binary"

if [ -r "$CONFIG_FILE" ]; then
	set +u
	# shellcheck disable=SC1090
	. "$CONFIG_FILE"
	set -u
	BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-${LUKS_BUILD_OUTPUT_DIR:-}}"
fi

if [ -z "$BUILD_OUTPUT_DIR" ]; then
	BUILD_OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

mkdir -p "$BUILD_OUTPUT_DIR"

for arg in "$@"; do
	case "$arg" in
		bump|--bump)
			BUMP_MODE="bump"
			;;
		source|--source)
			BUILD_MODE="source"
			;;
		binary|--binary)
			BUILD_MODE="binary"
			;;
		*)
			echo "Usage: $0 [bump|--bump] [source|--source|binary|--binary]" >&2
			exit 2
			;;
	esac
done

case "$BUMP_MODE" in
	"" )
		;;
	bump)
		# Increment patch version in debian/changelog when explicitly requested.
		CL="debian/changelog"
		cur="$(head -1 "$CL" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
		base="${cur%%~*}"

		debrev=""
		upstream="$base"
		if [[ "$base" == *-* ]]; then
			upstream="${base%-*}"
			debrev="${base##*-}"
		fi

		IFS='.' read -r major minor patch extra <<<"$upstream"
		if [[ -n "${extra:-}" ]] || ! [[ "${major:-}" =~ ^[0-9]+$ && "${minor:-}" =~ ^[0-9]+$ && "${patch:-}" =~ ^[0-9]+$ ]]; then
			echo "Cannot auto-bump non-semver upstream version: $cur" >&2
			exit 2
		fi

		patch=$(( patch + 1 ))
		new="${major}.${minor}.${patch}"
		if [ -n "$debrev" ]; then
			new="${new}-${debrev}"
		fi

		sed -i "1s|($cur)|($new)|" "$CL"
		echo "Version: $cur -> $new"
		;;
esac

if [ -z "$BUMP_MODE" ]; then
	cur="$(head -1 debian/changelog | sed -n 's/.*(\([^)]*\)).*/\1/p')"
	echo "Version unchanged: $cur"
fi

if [ "$BUILD_MODE" = "source" ]; then
	echo "[1/2] Building source package"
	dpkg-buildpackage -S -sa
else
	echo "[1/2] Building binary package"
	dpkg-buildpackage -us -uc -b
fi

echo "[2/2] Artifacts"
SRC_NAME="$(dpkg-parsechangelog -S Source)"
CUR_VERSION="$(dpkg-parsechangelog -S Version)"
CHANGES_FILE="${DEFAULT_OUTPUT_DIR}/${SRC_NAME}_${CUR_VERSION}_$(dpkg-architecture -qDEB_BUILD_ARCH).changes"

if [ "$BUILD_OUTPUT_DIR" != "$DEFAULT_OUTPUT_DIR" ]; then
	if [ -f "$CHANGES_FILE" ]; then
		while read -r file_name; do
			[ -n "$file_name" ] || continue
			if [ -f "${DEFAULT_OUTPUT_DIR}/${file_name}" ]; then
				mv -f "${DEFAULT_OUTPUT_DIR}/${file_name}" "${BUILD_OUTPUT_DIR}/"
			fi
		done < <(awk '/^Files:/ {in_files=1; next} in_files && NF==5 {print $5} in_files && NF!=5 {exit}' "$CHANGES_FILE")
		mv -f "$CHANGES_FILE" "${BUILD_OUTPUT_DIR}/"
	else
		for artifact in "${DEFAULT_OUTPUT_DIR}"/*_"${CUR_VERSION}"_*; do
			[ -e "$artifact" ] || continue
			mv -f "$artifact" "${BUILD_OUTPUT_DIR}/"
		done
	fi
fi

ls -1 "${BUILD_OUTPUT_DIR}"/luks-root-smartcard-tools_* || true
