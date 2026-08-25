#!/bin/sh
#
# fetch-recovery.sh — download a macOS Sequoia recovery image, no USB stick needed
#
# This replaces the 15GB "download the installer app, then createinstallmedia onto
# a USB" dance. macrecovery pulls Apple's ~700MB BaseSystem image; OpenCore's picker
# boots it directly, and "Reinstall macOS" streams the rest over ethernet.
#
# Why the odd board id: macrecovery asks Apple "what is the latest OS for this Mac".
# MacPro7,1 (Mac-27AD2F918AE68F61) is still supported by macOS Tahoe 26, so asking as
# MacPro7,1 gets you Tahoe. iMac19,1 (Mac-AA95B1DDAB278B95) tops out at Sequoia 15.7.4,
# so we ask as that instead. The recovery image is not tied to the SMBIOS you boot with.
#
# Usage:
#   ./tools/fetch-recovery.sh                 # into ./tools/.cache/recovery
#   ./tools/fetch-recovery.sh /Volumes/Boot   # straight onto a target volume
#   ./tools/fetch-recovery.sh --tahoe         # macOS Tahoe 26 instead
#

set -eu

OC_VERSION=1.0.7
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CACHE="$REPO_ROOT/tools/.cache"

BOARD=Mac-AA95B1DDAB278B95   # iMac19,1 -> latest is Sequoia 15.7.4
LABEL="macOS Sequoia 15"
DEST=""

while [ $# -gt 0 ]; do
	case "$1" in
		--tahoe) BOARD=Mac-27AD2F918AE68F61; LABEL="macOS Tahoe 26"; shift ;;
		--board) BOARD=$2; LABEL="board $2"; shift 2 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) DEST=$1; shift ;;
	esac
done

if [ -z "$DEST" ]; then
	# No destination given: use the cache, creating it if this is the first run.
	DEST="$CACHE/recovery"
	mkdir -p "$DEST"
elif [ ! -d "$DEST" ]; then
	# An explicit destination must already exist — if it does not, the volume is
	# probably not mounted, and silently creating a directory would hide that.
	echo "ERROR: destination does not exist: $DEST" >&2
	echo "Is that volume mounted? Omit the argument to download into the cache." >&2
	exit 1
fi

# ------------------------------------------------------------- macrecovery
MR="$CACHE/oc/Utilities/macrecovery/macrecovery.py"
if [ ! -f "$MR" ]; then
	echo "Fetching OpenCore $OC_VERSION utilities..."
	mkdir -p "$CACHE"
	ZIP="$CACHE/OpenCore-$OC_VERSION-RELEASE.zip"
	if [ ! -f "$ZIP" ]; then
		curl -fsSL --retry 3 --max-time 300 -o "$ZIP" \
			"https://github.com/acidanthera/OpenCorePkg/releases/download/$OC_VERSION/OpenCore-$OC_VERSION-RELEASE.zip"
	fi
	mkdir -p "$CACHE/oc"
	unzip -q -o "$ZIP" "Utilities/macrecovery/*" -d "$CACHE/oc"
fi

echo "Downloading $LABEL recovery image"
echo "  board id:    $BOARD"
echo "  destination: $DEST/com.apple.recovery.boot"
echo "  size:        roughly 700MB — this is not the full installer, the rest"
echo "               streams over ethernet during the install itself."
echo

cd "$DEST"

# macrecovery.py draws a progress bar using os.get_terminal_size(), which raises
# OSError("Inappropriate ioctl for device") the moment stdout is not a TTY — so it
# dies under SSH, cron, pipes, or any non-interactive run. Give it a pty when it
# does not have one so the download works headless.
if [ -t 1 ]; then
	python3 "$MR" -b "$BOARD" -os latest download
else
	echo "(no tty — running macrecovery under a pty so its progress bar works)"
	script -q /dev/null python3 "$MR" -b "$BOARD" -os latest download
fi

echo
if [ -f "$DEST/com.apple.recovery.boot/BaseSystem.dmg" ]; then
	echo "Done:"
	ls -lh "$DEST/com.apple.recovery.boot/"
	echo
	echo "Next: put com.apple.recovery.boot at the ROOT of a volume OpenCore can see"
	echo "      (any HFS+/APFS volume, or an EFI partition). With ScanPolicy 0 it"
	echo "      shows up in the picker as a macOS recovery entry."
else
	echo "ERROR: BaseSystem.dmg is missing — the download did not complete." >&2
	exit 1
fi
