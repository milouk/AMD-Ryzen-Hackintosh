#!/bin/sh
#
# fetch-wifi-kexts.sh — download the Broadcom Wi-Fi restoration kexts into EFI/OC/Kexts
#
# Apple removed IO80211FamilyLegacy.kext from macOS Sequoia, which is what killed
# native Wi-Fi for every Broadcom card (BCM94360, BCM943602, Fenvi T919, ...).
# The fix is to inject the Ventura-era networking stack instead. Two of these three
# kexts are Apple binaries, so they are NOT committed to this repository — they are
# pulled from the OpenCore Legacy Patcher payloads at setup time instead.
#
# Run this once after cloning, before copying EFI/ to your EFI partition.
#
# Usage:  ./tools/fetch-wifi-kexts.sh
#

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
KEXTS_DIR="$REPO_ROOT/EFI/OC/Kexts"
BASE="https://raw.githubusercontent.com/dortania/OpenCore-Legacy-Patcher/main/payloads/Kexts"

# bundle name : source path under payloads/Kexts
SOURCES="
AMFIPass.kext|Acidanthera/AMFIPass-v1.4.1-RELEASE.zip
IOSkywalkFamily.kext|Wifi/IOSkywalkFamily-v1.2.0.zip
IO80211FamilyLegacy.kext|Wifi/IO80211FamilyLegacy-v1.0.0.zip
"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "Fetching Broadcom Wi-Fi kexts into $KEXTS_DIR"
echo

for entry in $SOURCES; do
	bundle=${entry%%|*}
	src=${entry#*|}
	archive=$(basename "$src")

	printf '  %-26s <- %s\n' "$bundle" "$archive"

	if ! curl -fsSL --retry 3 --max-time 300 -o "$TMP/$archive" "$BASE/$src"; then
		echo "ERROR: failed to download $BASE/$src" >&2
		exit 1
	fi

	rm -rf "$TMP/extract"
	mkdir -p "$TMP/extract"
	unzip -q -o "$TMP/$archive" -d "$TMP/extract"
	rm -rf "$TMP/extract/__MACOSX"

	if [ ! -d "$TMP/extract/$bundle" ]; then
		echo "ERROR: $archive did not contain $bundle" >&2
		exit 1
	fi

	rm -rf "${KEXTS_DIR:?}/$bundle"
	cp -R "$TMP/extract/$bundle" "$KEXTS_DIR/$bundle"
done

echo
echo "Verifying bundles..."
FAIL=0
for path in \
	"AMFIPass.kext/Contents/MacOS/AMFIPass" \
	"IOSkywalkFamily.kext/Contents/MacOS/IOSkywalkFamily" \
	"IO80211FamilyLegacy.kext/Contents/MacOS/IO80211FamilyLegacy" \
	"IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext/Contents/MacOS/AirPortBrcmNIC"
do
	if [ -f "$KEXTS_DIR/$path" ]; then
		printf '  OK    %s\n' "$path"
	else
		printf '  MISS  %s\n' "$path"
		FAIL=1
	fi
done

echo
if [ "$FAIL" -ne 0 ]; then
	echo "Some bundles are incomplete. Do NOT boot with the IOSkywalkFamily block enabled." >&2
	exit 1
fi

echo "Done. All four bundles are in place."
echo "AirPortBrcmNIC matches pci14e4,43ba (BCM43602) — the chip in the BCM943602CS."
