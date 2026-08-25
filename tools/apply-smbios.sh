#!/bin/sh
#
# apply-smbios.sh — generate MacPro7,1 SMBIOS values and write them into a config.plist
#
# Replaces the manual GenSMBIOS + ProperTree dance. Generates Serial / MLB / UUID
# with macserial (downloading the OpenCore utilities if needed), reads the real
# onboard ethernet MAC for ROM, and patches all four into the target config.plist.
#
# Usage:
#   ./tools/apply-smbios.sh /Volumes/EFI/EFI/OC/config.plist
#   ./tools/apply-smbios.sh --rom a4b1c2d3e4f5 /path/to/config.plist   # explicit MAC
#   ./tools/apply-smbios.sh --dry-run /path/to/config.plist            # just show values
#
# Run this against the config.plist on your EFI partition, NOT the one in the
# repo — these values are your machine's identity and the repo is public.
#

set -eu

OC_VERSION=1.0.7
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ROM=""
DRY_RUN=0
TARGET=""

while [ $# -gt 0 ]; do
	case "$1" in
		--rom) ROM=$(printf '%s' "$2" | tr -d ':-' | tr 'A-Z' 'a-z'); shift 2 ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) TARGET=$1; shift ;;
	esac
done

if [ "$DRY_RUN" -eq 0 ] && [ -z "$TARGET" ]; then
	echo "ERROR: give me the config.plist to patch, or use --dry-run" >&2
	echo "Usage: $0 [--rom <mac>] [--dry-run] <path-to-config.plist>" >&2
	exit 1
fi

if [ -n "$TARGET" ] && [ ! -f "$TARGET" ]; then
	echo "ERROR: no such file: $TARGET" >&2
	exit 1
fi

# Real SMBIOS belongs on the EFI partition and in the private working repo.
# It must never land in the public one. Decide by the target's git remote rather
# than by path, so this stays correct from whichever checkout the script is run.
PUBLIC_REPO_NAME="AMD-Ryzen-Hackintosh"
if [ -n "$TARGET" ]; then
	TARGET_DIR=$(CDPATH='' cd -- "$(dirname -- "$TARGET")" && pwd)
	REMOTE=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)
	case "$(basename "${REMOTE%.git}")" in
		"$PUBLIC_REPO_NAME")
			echo "REFUSING: that config.plist belongs to $PUBLIC_REPO_NAME, the PUBLIC repo." >&2
			echo "These values are your machine's identity. Write them to your EFI" >&2
			echo "partition, or to the private working repo, instead." >&2
			exit 1 ;;
	esac
	if [ -n "$REMOTE" ]; then
		echo "NOTE: target is inside git repo $(basename "${REMOTE%.git}") — make sure that one is private."
	fi
fi

# ---------------------------------------------------------------- macserial
MACSERIAL=""
for c in \
	"$REPO_ROOT/tools/.cache/oc/Utilities/macserial/macserial" \
	"$(command -v macserial 2>/dev/null || true)"
do
	[ -n "$c" ] && [ -x "$c" ] && MACSERIAL=$c && break
done

if [ -z "$MACSERIAL" ]; then
	echo "macserial not found — fetching OpenCore $OC_VERSION utilities..."
	CACHE="$REPO_ROOT/tools/.cache"
	mkdir -p "$CACHE"
	ZIP="$CACHE/OpenCore-$OC_VERSION-RELEASE.zip"
	if [ ! -f "$ZIP" ]; then
		curl -fsSL --retry 3 --max-time 300 -o "$ZIP" \
			"https://github.com/acidanthera/OpenCorePkg/releases/download/$OC_VERSION/OpenCore-$OC_VERSION-RELEASE.zip"
	fi
	rm -rf "$CACHE/oc"
	mkdir -p "$CACHE/oc"
	unzip -q -o "$ZIP" "Utilities/macserial/*" -d "$CACHE/oc"
	MACSERIAL="$CACHE/oc/Utilities/macserial/macserial"
	chmod +x "$MACSERIAL"
fi

# ------------------------------------------------------------------- values
SET=$("$MACSERIAL" --model MacPro7,1 --num 1 | head -1)
SERIAL=$(printf '%s' "$SET" | awk -F' *\\| *' '{print $1}')
MLB=$(printf '%s' "$SET" | awk -F' *\\| *' '{print $2}')
UUID=$(python3 -c 'import uuid;print(str(uuid.uuid4()).upper())')

ETH_DEV=""
if [ -z "$ROM" ]; then
	# Must be the interface macOS calls Ethernet. Never guess: ROM is what ties
	# this machine to Apple's services, and a Wi-Fi MAC here breaks iServices in
	# a way that looks like an Apple-account problem rather than a config error.
	ETH_DEV=$(networksetup -listallhardwareports 2>/dev/null |
		awk '/Hardware Port: Ethernet/{getline; print $2; exit}')
	if [ -n "$ETH_DEV" ]; then
		ROM=$(ifconfig "$ETH_DEV" 2>/dev/null | awk '/ether/{gsub(":","",$2); print $2; exit}')
	fi
fi

if [ -z "$ROM" ]; then
	echo "WARNING: no Ethernet hardware port found on this machine."
	echo "         Not guessing — en0 here may well be Wi-Fi, and the wrong ROM"
	echo "         breaks iMessage/FaceTime in a way that is painful to diagnose."
	echo "         Run this on the Ryzentosh, or pass --rom <ethernet-mac>."
	echo "         ROM will be left UNCHANGED in the config."
else
	echo "Ethernet MAC for ROM: $ROM  (device $ETH_DEV)"
fi

cat <<EOF

  SystemSerialNumber  $SERIAL
  MLB                 $MLB
  SystemUUID          $UUID
  ROM                 ${ROM:-<unchanged>}

EOF

echo "VERIFY THIS SERIAL before trusting it:"
echo "  https://checkcoverage.apple.com/  ->  enter $SERIAL"
echo "  You want \"unable to check coverage\". If it shows a real purchase date,"
echo "  re-run this script to get a different set."
echo

if [ "$DRY_RUN" -eq 1 ]; then
	echo "(dry run — nothing written)"
	exit 0
fi

# -------------------------------------------------------------------- patch
cp "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)"

# Deliberately a text-level edit, not a plistlib round-trip. plistlib would
# reserialise the file and strip all 78 explanatory XML comments from it, which
# is most of what makes this config maintainable. Each of the four keys appears
# exactly once, so scoped regex replacement is safe here.
python3 - "$TARGET" "$SERIAL" "$MLB" "$UUID" "${ROM:-}" <<'PY'
import base64, plistlib, re, sys

path, serial, mlb, uuid_, rom = sys.argv[1:6]
src = open(path, encoding='utf-8').read()

edits = [('MLB', 'string', mlb),
         ('SystemSerialNumber', 'string', serial),
         ('SystemUUID', 'string', uuid_)]
if rom:
    edits.append(('ROM', 'data', base64.b64encode(bytes.fromhex(rom)).decode()))

for key, tag, value in edits:
    pattern = re.compile(
        r'(<key>' + re.escape(key) + r'</key>\s*<' + tag + r'>)(.*?)(</' + tag + r'>)',
        re.DOTALL)
    src, n = pattern.subn(lambda m: m.group(1) + value + m.group(3), src, count=1)
    if n != 1:
        sys.exit(f"ERROR: could not locate <key>{key}</key> in {path} — aborted, "
                 "file unchanged on disk beyond the backup already taken")

open(path, 'w', encoding='utf-8').write(src)

# Read back through a real plist parser to prove we did not corrupt anything.
with open(path, 'rb') as f:
    g = plistlib.load(f)['PlatformInfo']['Generic']
assert g['MLB'] == mlb and g['SystemSerialNumber'] == serial and g['SystemUUID'] == uuid_
if rom:
    assert g['ROM'] == bytes.fromhex(rom)

print(f"Patched {path}")
print(f"  comments preserved: {src.count('<!--')}")
PY

echo "Backup written alongside as *.bak-<timestamp>"
echo "Now validate:  ocvalidate \"$TARGET\""
