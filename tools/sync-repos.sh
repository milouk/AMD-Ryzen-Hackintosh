#!/bin/sh
#
# sync-repos.sh — move EFI changes between the public repo and the working repo
#
#   AMD-Ryzen-Hackintosh  public,  SMBIOS stripped to placeholders
#   My-Ryzentosh          working, real Serial / MLB / UUID / ROM
#
# The only thing that must never cross is the SMBIOS block. Everything else —
# OpenCore binaries, kexts, drivers, resources, config, guide, tools — is shared.
#
#   --to-working   public -> working, KEEPING the working repo's real SMBIOS
#   --to-public    working -> public, REPLACING SMBIOS with placeholders
#
# Both directions back up the target config first and validate afterwards.
# Neither touches README.md: the two repos deliberately have different ones.
#
# Usage:
#   ./tools/sync-repos.sh --to-working
#   ./tools/sync-repos.sh --to-public --dry-run
#

set -eu

PUBLIC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORKING=${RYZENTOSH_WORKING:-"$(dirname -- "$PUBLIC")/My-Ryzentosh"}

PLACEHOLDER_MLB="M0000000000000001"
PLACEHOLDER_SERIAL="W00000000001"
PLACEHOLDER_UUID="00000000-0000-0000-0000-000000000000"
PLACEHOLDER_ROM="ESIzRFVm"   # 11:22:33:44:55:66

DIRECTION=""
DRY_RUN=0

while [ $# -gt 0 ]; do
	case "$1" in
		--to-working) DIRECTION=to-working; shift ;;
		--to-public)  DIRECTION=to-public;  shift ;;
		--dry-run)    DRY_RUN=1; shift ;;
		-h|--help)    sed -n '2,22p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 1 ;;
	esac
done

[ -z "$DIRECTION" ] && { echo "ERROR: pass --to-working or --to-public" >&2; exit 1; }

if [ ! -d "$WORKING/EFI/OC" ]; then
	echo "ERROR: working repo not found at $WORKING" >&2
	echo "Set RYZENTOSH_WORKING to its path." >&2
	exit 1
fi

case "$DIRECTION" in
	to-working) SRC=$PUBLIC; DST=$WORKING ;;
	to-public)  SRC=$WORKING; DST=$PUBLIC ;;
esac

echo "Source: $SRC"
echo "Target: $DST"
echo

# Warn about uncommitted work in the target — this overwrites files.
if git -C "$DST" rev-parse --git-dir >/dev/null 2>&1; then
	if [ -n "$(git -C "$DST" status --porcelain 2>/dev/null)" ]; then
		echo "WARNING: target repo has uncommitted changes:"
		git -C "$DST" status --short | sed 's/^/    /'
		echo "         They will be overwritten where files overlap."
		echo
	fi
fi

# ------------------------------------------------- remember target's SMBIOS
SAVED=$(python3 - "$DST/EFI/OC/config.plist" <<'PY'
import base64, plistlib, sys
try:
    g = plistlib.load(open(sys.argv[1], 'rb'))['PlatformInfo']['Generic']
except Exception:
    sys.exit(0)
print(g.get('MLB', ''))
print(g.get('SystemSerialNumber', ''))
print(g.get('SystemUUID', ''))
print(base64.b64encode(g.get('ROM', b'')).decode())
PY
)
OLD_MLB=$(printf '%s\n' "$SAVED" | sed -n 1p)
OLD_SERIAL=$(printf '%s\n' "$SAVED" | sed -n 2p)
OLD_UUID=$(printf '%s\n' "$SAVED" | sed -n 3p)
OLD_ROM=$(printf '%s\n' "$SAVED" | sed -n 4p)

if [ "$DIRECTION" = to-working ]; then
	KEEP_MLB=$OLD_MLB; KEEP_SERIAL=$OLD_SERIAL; KEEP_UUID=$OLD_UUID; KEEP_ROM=$OLD_ROM
	if [ "$KEEP_SERIAL" = "$PLACEHOLDER_SERIAL" ] || [ -z "$KEEP_SERIAL" ]; then
		echo "NOTE: the working repo currently holds placeholder SMBIOS."
		echo "      Nothing real to preserve — run tools/apply-smbios.sh afterwards."
	else
		echo "Preserving the working repo's real SMBIOS (serial ${KEEP_SERIAL%??????}******)"
	fi
else
	KEEP_MLB=$PLACEHOLDER_MLB
	KEEP_SERIAL=$PLACEHOLDER_SERIAL
	KEEP_UUID=$PLACEHOLDER_UUID
	KEEP_ROM=$PLACEHOLDER_ROM
	echo "Stripping SMBIOS to placeholders for the public repo"
fi
echo

if [ "$DRY_RUN" -eq 1 ]; then
	echo "Would copy: EFI/  tools/  .github/  UPGRADE-GUIDE.md"
	echo "Would leave alone: README.md, .gitignore, .git/"
	echo "(dry run — nothing written)"
	exit 0
fi

# ------------------------------------------------------------------- backup
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$PUBLIC/tools/.backups/sync-$DIRECTION-$STAMP.tar.gz"
mkdir -p "$PUBLIC/tools/.backups"
echo "Backing up target -> $BACKUP"
tar -czf "$BACKUP" -C "$DST" EFI UPGRADE-GUIDE.md 2>/dev/null || \
	tar -czf "$BACKUP" -C "$DST" EFI
echo "  $(du -h "$BACKUP" | cut -f1)"
echo

# --------------------------------------------------------------------- copy
echo "Syncing..."
rm -rf "$DST/EFI"
cp -R "$SRC/EFI" "$DST/EFI"
[ -d "$SRC/tools" ] && { rm -rf "$DST/tools"; cp -R "$SRC/tools" "$DST/tools"; }
[ -f "$SRC/UPGRADE-GUIDE.md" ] && cp "$SRC/UPGRADE-GUIDE.md" "$DST/UPGRADE-GUIDE.md"
# Workflows live in both repos. publish-mirror.yml no-ops outside the private
# one via its `if: github.repository == ...` guard, so syncing it is safe.
[ -d "$SRC/.github" ] && { rm -rf "$DST/.github"; cp -R "$SRC/.github" "$DST/.github"; }

# .gitignore is deliberately NOT synced. The two repos need different ones: the
# public repo excludes the Apple Wi-Fi kexts because it must not redistribute
# them, while the private repo tracks them so a clone is complete.

# Tool caches and backups are machine-local; never propagate them.
rm -rf "$DST/tools/.cache" "$DST/tools/.backups"

# ------------------------------------------------------ restore SMBIOS block
python3 - "$DST/EFI/OC/config.plist" "$KEEP_MLB" "$KEEP_SERIAL" "$KEEP_UUID" "$KEEP_ROM" <<'PY'
import base64, plistlib, re, sys

path, mlb, serial, uuid_, rom_b64 = sys.argv[1:6]
src = open(path, encoding='utf-8').read()

for key, tag, value in (('MLB', 'string', mlb),
                        ('SystemSerialNumber', 'string', serial),
                        ('SystemUUID', 'string', uuid_),
                        ('ROM', 'data', rom_b64)):
    if not value:
        continue
    pat = re.compile(r'(<key>' + re.escape(key) + r'</key>\s*<' + tag + r'>)(.*?)(</' + tag + r'>)',
                     re.DOTALL)
    src, n = pat.subn(lambda m: m.group(1) + value + m.group(3), src, count=1)
    if n != 1:
        sys.exit(f"ERROR: could not find <key>{key}</key> in {path}")

open(path, 'w', encoding='utf-8').write(src)

g = plistlib.load(open(path, 'rb'))['PlatformInfo']['Generic']
assert g['MLB'] == mlb and g['SystemSerialNumber'] == serial
print(f"  SMBIOS block set, {src.count('<!--')} comments preserved")
PY

# ------------------------------------------------------------------- verify
echo
echo "Verifying target..."
plutil -lint "$DST/EFI/OC/config.plist" >/dev/null || { echo "FAIL: malformed plist" >&2; exit 1; }
"$PUBLIC/tools/verify-efi.sh" "$DST/EFI" | sed 's/^/  /'

# Belt and braces: the public repo must never carry a real serial.
if [ "$DIRECTION" = to-public ]; then
	ACTUAL=$(python3 -c "
import plistlib,sys
print(plistlib.load(open(sys.argv[1],'rb'))['PlatformInfo']['Generic']['SystemSerialNumber'])
" "$DST/EFI/OC/config.plist")
	if [ "$ACTUAL" != "$PLACEHOLDER_SERIAL" ]; then
		echo "ABORT: public config still holds a non-placeholder serial!" >&2
		exit 1
	fi
	echo "  OK     public config carries placeholder SMBIOS only"
fi

echo
echo "Done. Review with:  git -C \"$DST\" diff --stat"
