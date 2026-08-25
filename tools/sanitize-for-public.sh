#!/bin/sh
#
# sanitize-for-public.sh — strip everything private out of an EFI tree, in place
#
# Two things must never reach the public mirror:
#   1. Real SMBIOS  — Serial, MLB, SystemUUID, ROM identify the machine to Apple
#   2. Apple's Wi-Fi kexts — IO80211FamilyLegacy and IOSkywalkFamily are Apple
#      binaries lifted from Ventura; the public repo fetches them at setup time
#      with tools/fetch-wifi-kexts.sh instead of redistributing them
#
# This is fail-closed. It records the real values BEFORE replacing them, then
# greps the whole output tree for them afterwards, and exits non-zero if any
# survive anywhere — config, docs, backups, anything.
#
# Usage:  ./tools/sanitize-for-public.sh <tree>
#         ./tools/sanitize-for-public.sh .        # in the checkout itself
#

set -eu

TREE=${1:-.}
CONFIG="$TREE/EFI/OC/config.plist"

PLACEHOLDER_MLB="M0000000000000001"
PLACEHOLDER_SERIAL="W00000000001"
PLACEHOLDER_UUID="00000000-0000-0000-0000-000000000000"
PLACEHOLDER_ROM_B64="ESIzRFVm"   # 11:22:33:44:55:66

[ -f "$CONFIG" ] || { echo "ERROR: no config.plist at $CONFIG" >&2; exit 1; }

echo "Sanitizing $TREE"

# ------------------------------------------- capture the real values first
REAL=$(python3 - "$CONFIG" <<'PY'
import base64, binascii, plistlib, sys
g = plistlib.load(open(sys.argv[1], 'rb'))['PlatformInfo']['Generic']
print(g.get('MLB', ''))
print(g.get('SystemSerialNumber', ''))
print(g.get('SystemUUID', ''))
print(base64.b64encode(g.get('ROM', b'')).decode())
print(binascii.hexlify(g.get('ROM', b'')).decode())
PY
)
REAL_MLB=$(printf '%s\n' "$REAL" | sed -n 1p)
REAL_SERIAL=$(printf '%s\n' "$REAL" | sed -n 2p)
REAL_UUID=$(printf '%s\n' "$REAL" | sed -n 3p)
REAL_ROM_B64=$(printf '%s\n' "$REAL" | sed -n 4p)
REAL_ROM_HEX=$(printf '%s\n' "$REAL" | sed -n 5p)

# --------------------------------------------------- replace with placeholders
python3 - "$CONFIG" "$PLACEHOLDER_MLB" "$PLACEHOLDER_SERIAL" \
                    "$PLACEHOLDER_UUID" "$PLACEHOLDER_ROM_B64" <<'PY'
import plistlib, re, sys
path, mlb, serial, uuid_, rom = sys.argv[1:6]
src = open(path, encoding='utf-8').read()
for key, tag, value in (('MLB', 'string', mlb),
                        ('SystemSerialNumber', 'string', serial),
                        ('SystemUUID', 'string', uuid_),
                        ('ROM', 'data', rom)):
    pat = re.compile(r'(<key>' + re.escape(key) + r'</key>\s*<' + tag + r'>)(.*?)(</' + tag + r'>)',
                     re.DOTALL)
    src, n = pat.subn(lambda m: m.group(1) + value + m.group(3), src, count=1)
    if n != 1:
        sys.exit(f"ERROR: could not find <key>{key}</key>")
open(path, 'w', encoding='utf-8').write(src)
g = plistlib.load(open(path, 'rb'))['PlatformInfo']['Generic']
assert g['SystemSerialNumber'] == serial and g['MLB'] == mlb
print(f"  SMBIOS replaced with placeholders, {src.count('<!--')} comments kept")
PY

# ------------------------------------------------- drop the Apple Wi-Fi kexts
for k in AMFIPass.kext IOSkywalkFamily.kext IO80211FamilyLegacy.kext; do
	if [ -e "$TREE/EFI/OC/Kexts/$k" ]; then
		rm -rf "$TREE/EFI/OC/Kexts/$k"
		echo "  removed EFI/OC/Kexts/$k"
	fi
done

# --------------------------------------------------- public .gitignore
cat > "$TREE/.gitignore" <<'IGNORE'
.DS_Store

# Broadcom Wi-Fi restoration kexts.
# IO80211FamilyLegacy.kext (with its AirPortBrcmNIC plugin) and IOSkywalkFamily.kext
# are Apple binaries lifted from macOS Ventura, so they are not redistributed here.
# Run ./tools/fetch-wifi-kexts.sh to pull all three from the OpenCore Legacy Patcher
# payloads before copying EFI/ to your EFI partition.
EFI/OC/Kexts/AMFIPass.kext/
EFI/OC/Kexts/IOSkywalkFamily.kext/
EFI/OC/Kexts/IO80211FamilyLegacy.kext/

# Tool working directories: downloaded OpenCore utilities, recovery images, and
# EFI backups taken by install-efi.sh. All reproducible or machine-specific.
tools/.cache/
tools/.backups/

# Never commit a config.plist carrying real SMBIOS values.
*.bak-*
IGNORE

# Machine-local junk that must never be published.
rm -rf "$TREE/tools/.cache" "$TREE/tools/.backups"
find "$TREE" -name '*.bak-*' -delete 2>/dev/null || true
find "$TREE" -name '.DS_Store' -delete 2>/dev/null || true

# ---------------------------------------------------------------- fail closed
echo "Auditing the sanitized tree..."
FAIL=0
for secret in "$REAL_MLB" "$REAL_SERIAL" "$REAL_UUID" "$REAL_ROM_B64" "$REAL_ROM_HEX"; do
	# Skip empties and values that were already placeholders.
	case "$secret" in
		''|"$PLACEHOLDER_MLB"|"$PLACEHOLDER_SERIAL"|"$PLACEHOLDER_UUID"|"$PLACEHOLDER_ROM_B64") continue ;;
	esac
	if grep -rIlF --exclude-dir=.git "$secret" "$TREE" 2>/dev/null | grep -q .; then
		echo "  LEAK: a private value still appears in:" >&2
		grep -rIlF --exclude-dir=.git "$secret" "$TREE" 2>/dev/null | sed 's/^/    /' >&2
		FAIL=1
	fi
done

for k in AMFIPass.kext IOSkywalkFamily.kext IO80211FamilyLegacy.kext; do
	if [ -e "$TREE/EFI/OC/Kexts/$k" ]; then
		echo "  LEAK: $k is still present" >&2
		FAIL=1
	fi
done

ACTUAL=$(python3 -c "
import plistlib,sys
print(plistlib.load(open(sys.argv[1],'rb'))['PlatformInfo']['Generic']['SystemSerialNumber'])
" "$CONFIG")
if [ "$ACTUAL" != "$PLACEHOLDER_SERIAL" ]; then
	echo "  LEAK: serial is '$ACTUAL', expected the placeholder" >&2
	FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
	echo >&2
	echo "SANITIZE FAILED — do not publish this tree." >&2
	exit 1
fi

echo "  OK     no private SMBIOS value appears anywhere in the tree"
echo "  OK     no Apple Wi-Fi kexts present"
echo "  OK     config carries placeholder SMBIOS"
echo
echo "Safe to publish."
