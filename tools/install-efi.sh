#!/bin/sh
#
# install-efi.sh — safely install or upgrade this repo's EFI on an EFI partition
#
# Built so that an OpenCore upgrade cannot cost you anything:
#   - only ever writes to an EFI system partition, never a data volume
#   - archives what is there first, and proves the archive restores byte-for-byte
#   - replaces EFI/BOOT and EFI/OC only — EFI/Microsoft and any other vendor's
#     boot files on the same partition are left exactly as they are
#   - carries the SMBIOS (Serial / MLB / UUID / ROM) of the EFI being replaced
#     over to the new one, so the machine keeps its identity and iServices
#   - shows every setting that differs from the config being replaced
#   - copies the new files next to the old ones, verifies the copy, and only
#     then swaps them in
#   - --restore puts any earlier archive back
#
# Usage:
#   ./tools/install-efi.sh --list                 # show candidate EFI partitions
#   ./tools/install-efi.sh --dry-run disk0s1      # everything except writing
#   ./tools/install-efi.sh disk0s1                # back up + install onto disk0s1
#   ./tools/install-efi.sh --backup-only disk0s1  # just archive what is there now
#   ./tools/install-efi.sh --restore tools/.backups/EFI-disk0s1-<stamp>.tar.gz disk0s1
#
#   --fresh   do not carry SMBIOS over; install the repo's config as it is
#   --yes     do not ask for confirmation
#
# Recommended upgrade path: install onto a USB stick's EFI partition first,
# boot from it once (F11 on MSI boards), and only then install onto the
# internal disk. The stick stays behind as a known-good rescue bootloader.
#
# Needs sudo to mount EFI partitions.
#

set -eu

OC_VERSION=1.0.8
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BACKUP_DIR="$REPO_ROOT/tools/.backups"
CACHE="$REPO_ROOT/tools/.cache"
PLACEHOLDER_SERIAL="W00000000001"

BACKUP_ONLY=0
DRY_RUN=0
FRESH=0
YES=0
RESTORE=""
DEV=""

while [ $# -gt 0 ]; do
	case "$1" in
		--list)
			echo "EFI partitions on this machine:"
			echo
			diskutil list | grep -E "^/dev/|EFI" | sed 's/^/  /'
			echo
			echo "Identify the disk you want by name above, then pass its EFI slice"
			echo "(the 'EFI' row, e.g. disk2s1) to this script."
			exit 0 ;;
		--backup-only) BACKUP_ONLY=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--fresh) FRESH=1; shift ;;
		--yes) YES=1; shift ;;
		--restore) RESTORE=$2; shift 2 ;;
		-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
		*) DEV=$1; shift ;;
	esac
done

if [ -z "$DEV" ]; then
	echo "ERROR: which EFI partition? Run '$0 --list' first." >&2
	exit 1
fi

if [ -n "$RESTORE" ] && [ ! -f "$RESTORE" ]; then
	echo "ERROR: no such archive: $RESTORE" >&2
	exit 1
fi

DEV=${DEV#/dev/}

# --------------------------------------------------- confirm it IS an ESP
FSTYPE=$(diskutil info "$DEV" 2>/dev/null | awk -F': *' '/Type \(Bundle\)/{print $2}' | tr -d ' ')
VOLNAME=$(diskutil info "$DEV" 2>/dev/null | awk -F': *' '/Volume Name/{print $2}' | sed 's/ *$//')

if [ "$FSTYPE" != "msdos" ] || [ "$VOLNAME" != "EFI" ]; then
	echo "REFUSING: $DEV does not look like an EFI system partition." >&2
	echo "  Volume Name: ${VOLNAME:-<none>}   Type: ${FSTYPE:-<unknown>}" >&2
	echo "  Expected an msdos partition named EFI. Run '$0 --list'." >&2
	exit 1
fi

echo "Target: /dev/$DEV  (EFI system partition)"
diskutil info "$DEV" | grep -E "Part of Whole|Device / Media Name|Disk Size" | sed 's/^/  /'
echo

MOUNTED_BY_US=0
MP=$(diskutil info "$DEV" 2>/dev/null | awk -F': *' '/Mount Point/{print $2}' | sed 's/ *$//')
if [ -z "$MP" ]; then
	echo "Mounting $DEV (sudo)..."
	sudo diskutil mount "$DEV" >/dev/null
	MOUNTED_BY_US=1
	MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/{print $2}' | sed 's/ *$//')
fi
[ -z "$MP" ] && { echo "ERROR: could not mount $DEV" >&2; exit 1; }
echo "Mounted at $MP"

# Only reach for sudo when the mount is not writable by us.
SUDO=""
[ -w "$MP" ] || SUDO="sudo"

TMP=$(mktemp -d)
cleanup() {
	rm -rf "$TMP"
	if [ "$MOUNTED_BY_US" -eq 1 ]; then
		sudo diskutil unmount "$DEV" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT INT TERM

# Compare two trees, ignoring the junk macOS scatters over FAT volumes.
same_tree() {
	diff -r -x '.DS_Store' -x '._*' "$1" "$2" >/dev/null 2>&1
}

# ------------------------------------------------------------- back it up
STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE=""
if [ -d "$MP/EFI" ]; then
	ARCHIVE="$BACKUP_DIR/EFI-$DEV-$STAMP.tar.gz"
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "Would back up existing EFI -> $ARCHIVE"
		ARCHIVE=""
	else
		mkdir -p "$BACKUP_DIR"
		echo "Backing up existing EFI -> $ARCHIVE"
		# FAT has no extended attributes; macOS fakes them as ._ files. Leave those out.
		# The flags that say so outright are missing from older bsdtar (Catalina).
		TAR_FLAGS=""
		if tar --no-xattrs --no-mac-metadata -cf /dev/null -T /dev/null 2>/dev/null; then
			TAR_FLAGS="--no-xattrs --no-mac-metadata"
		fi
		COPYFILE_DISABLE=1 tar $TAR_FLAGS --exclude "._*" --exclude ".DS_Store" \
			-czf "$ARCHIVE" -C "$MP" EFI
		# An archive nobody has tried to restore is a hope, not a backup.
		mkdir "$TMP/backup-check"
		tar -xzf "$ARCHIVE" -C "$TMP/backup-check"
		if ! same_tree "$MP/EFI" "$TMP/backup-check/EFI"; then
			echo "ABORT: the backup does not match what is on $DEV. Nothing was written." >&2
			exit 1
		fi
		rm -rf "$TMP/backup-check"
		echo "  $(du -h "$ARCHIVE" | cut -f1) archived, restores byte-for-byte"
	fi
else
	echo "No existing EFI folder on $DEV — nothing to back up."
fi

if [ "$BACKUP_ONLY" -eq 1 ]; then
	echo "Backup only — not writing anything. Done."
	exit 0
fi

# ------------------------------------------------------ stage what goes in
STAGE="$TMP/stage"
mkdir -p "$STAGE"
echo

if [ -n "$RESTORE" ]; then
	echo "Staging the archive to restore: $RESTORE"
	tar -xzf "$RESTORE" -C "$STAGE"
	if [ ! -f "$STAGE/EFI/OC/OpenCore.efi" ]; then
		echo "REFUSING: that archive does not contain EFI/OC/OpenCore.efi." >&2
		exit 1
	fi
	# Put back every folder the archive holds, exactly as it was.
	DIRS=$(cd "$STAGE/EFI" && ls)
else
	echo "Staging this repo's EFI..."
	mkdir "$STAGE/EFI"
	# -X: no extended attributes, so nothing turns into ._ files on FAT.
	cp -RX "$REPO_ROOT/EFI/BOOT" "$REPO_ROOT/EFI/OC" "$STAGE/EFI/"
	find "$STAGE" -name '.DS_Store' -delete
	DIRS="BOOT OC"

	# ---------------------------------------- keep the machine's identity
	LIVE="$MP/EFI/OC/config.plist"
	if [ "$FRESH" -eq 0 ] && [ -f "$LIVE" ]; then
		python3 - "$LIVE" "$STAGE/EFI/OC/config.plist" "$PLACEHOLDER_SERIAL" <<'PY'
import base64, plistlib, re, sys

live_path, new_path, placeholder = sys.argv[1:4]
try:
    live = plistlib.load(open(live_path, 'rb'))['PlatformInfo']['Generic']
except Exception as e:
    sys.exit(f"ABORT: cannot read the config being replaced ({e}). "
             "Use --fresh to install without carrying SMBIOS over.")

serial = live.get('SystemSerialNumber', '')
if not serial or serial == placeholder:
    print("  existing config has placeholder SMBIOS — nothing to carry over")
    sys.exit(0)

# A serial encodes the Mac model. Carrying one across a model change (the old
# iMacPro1,1 EFI to this MacPro7,1 one) would produce an identity Apple rejects.
new_model = plistlib.load(open(new_path, 'rb'))['PlatformInfo']['Generic'].get('SystemProductName', '')
live_model = live.get('SystemProductName', '')
if live_model != new_model:
    print(f"  existing EFI is {live_model or 'an unknown model'}, this one is {new_model} — "
          "its serial does not apply,")
    print("  so SMBIOS is NOT carried over; the repo config's own values are used")
    sys.exit(0)

# Text-level edit, like apply-smbios.sh, so the config's comments survive.
src = open(new_path, encoding='utf-8').read()
for key, tag, value in (
        ('MLB', 'string', live.get('MLB', '')),
        ('SystemSerialNumber', 'string', serial),
        ('SystemUUID', 'string', live.get('SystemUUID', '')),
        ('ROM', 'data', base64.b64encode(live.get('ROM', b'')).decode())):
    pat = re.compile(r'(<key>' + re.escape(key) + r'</key>\s*<' + tag + r'>)(.*?)(</' + tag + r'>)',
                     re.DOTALL)
    src, n = pat.subn(lambda m: m.group(1) + value + m.group(3), src, count=1)
    if n != 1:
        sys.exit(f"ABORT: could not find <key>{key}</key> in the new config")
open(new_path, 'w', encoding='utf-8').write(src)

new = plistlib.load(open(new_path, 'rb'))['PlatformInfo']['Generic']
for key in ('MLB', 'SystemSerialNumber', 'SystemUUID', 'ROM'):
    if new.get(key) != live.get(key):
        sys.exit(f"ABORT: {key} did not carry over")
print(f"  SMBIOS carried over from the existing EFI (serial {serial[:-6]}******)")
PY
	fi

	# ------------------------------------- what changes besides the binaries
	if [ -f "$LIVE" ]; then
		echo
		echo "Settings that differ from the config being replaced:"
		python3 - "$LIVE" "$STAGE/EFI/OC/config.plist" <<'PY'
import plistlib, sys

try:
    old = plistlib.load(open(sys.argv[1], 'rb'))
except Exception as e:
    print(f"  (existing config is unreadable: {e})")
    sys.exit(0)
new = plistlib.load(open(sys.argv[2], 'rb'))
SECRET = ('MLB', 'SystemSerialNumber', 'SystemUUID', 'ROM')
out = []

def show(v):
    if isinstance(v, bytes):
        v = v.hex()
    s = repr(v)
    return s if len(s) <= 60 else s[:57] + '...'

def walk(a, b, path):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            p = f"{path} > {k}" if path else k
            if k not in a:
                out.append(f"  added    {p} = {show(b[k])}")
            elif k not in b:
                out.append(f"  REMOVED  {p} (was {show(a[k])})")
            else:
                walk(a[k], b[k], p)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append(f"  changed  {path}: {len(a)} entries -> {len(b)} entries")
        for i, (x, y) in enumerate(zip(a, b)):
            walk(x, y, f"{path}[{i}]")
    elif a != b:
        if path.rsplit(' > ', 1)[-1] in SECRET:
            out.append(f"  CHANGED  {path} (values hidden)")
        else:
            out.append(f"  changed  {path}: {show(a)} -> {show(b)}")

walk(old, new, '')
print('\n'.join(out) if out else "  none — only the binaries change")
PY
		echo "Anything listed as changed or REMOVED that you set by hand on the EFI"
		echo "partition is not in this repo, and will not survive the install."
	fi

	# ------------------------------------------------- preflight the result
	echo
	echo "Verifying the EFI we are about to install..."
	if ! "$REPO_ROOT/tools/verify-efi.sh" "$STAGE/EFI" >/dev/null 2>&1; then
		echo "REFUSING: tools/verify-efi.sh fails on the staged EFI." >&2
		echo "Run it directly to see why. Most likely you have not run" >&2
		echo "tools/fetch-wifi-kexts.sh yet." >&2
		exit 1
	fi
	echo "  staged EFI is complete and internally consistent"

	OCVALIDATE="$CACHE/oc-$OC_VERSION/Utilities/ocvalidate/ocvalidate"
	if [ ! -x "$OCVALIDATE" ]; then
		ZIP="$CACHE/OpenCore-$OC_VERSION-RELEASE.zip"
		mkdir -p "$CACHE/oc-$OC_VERSION"
		if [ -f "$ZIP" ] || curl -fsSL --retry 3 --max-time 300 -o "$ZIP" \
			"https://github.com/acidanthera/OpenCorePkg/releases/download/$OC_VERSION/OpenCore-$OC_VERSION-RELEASE.zip"
		then
			unzip -q -o "$ZIP" "Utilities/ocvalidate/*" -d "$CACHE/oc-$OC_VERSION"
			chmod +x "$OCVALIDATE"
		fi
	fi
	if [ -x "$OCVALIDATE" ]; then
		if ! "$OCVALIDATE" "$STAGE/EFI/OC/config.plist" >"$TMP/ocvalidate.log" 2>&1; then
			sed 's/^/  /' "$TMP/ocvalidate.log" >&2
			echo "REFUSING: ocvalidate $OC_VERSION rejects the staged config." >&2
			exit 1
		fi
		echo "  ocvalidate $OC_VERSION: no issues"
	else
		echo "  WARNING: could not fetch ocvalidate $OC_VERSION — schema not checked"
	fi
fi

# ------------------------------------------------------------ room to swap
# Old and new sit side by side on the partition until the swap.
NEED=$(du -sk "$STAGE/EFI" | cut -f1)
FREE=$(df -k "$MP" | awk 'NR==2{print $4}')
if [ "$NEED" -ge "$FREE" ]; then
	echo "REFUSING: need ${NEED}K on $DEV to stage the new files, only ${FREE}K free." >&2
	echo "Nothing was written." >&2
	exit 1
fi

echo
echo "Will replace on /dev/$DEV: $(echo $DIRS | sed 's/\([^ ]*\)/EFI\/\1/g')"
OTHERS=""
for path in "$MP/EFI"/*; do
	[ -e "$path" ] || continue
	name=$(basename "$path")
	keep=1
	for d in $DIRS; do
		[ "$d" = "$name" ] && keep=0
	done
	[ "$keep" -eq 1 ] && OTHERS="$OTHERS EFI/$name"
done
[ -n "$OTHERS" ] && echo "Will leave untouched:  $OTHERS"

if [ "$DRY_RUN" -eq 1 ]; then
	echo
	echo "(dry run — nothing written)"
	exit 0
fi

# -------------------------------------------------------------- install
if [ "$YES" -eq 0 ]; then
	echo
	printf 'Proceed? [y/N] '
	read -r ANSWER
	case "$ANSWER" in
		[yY]|[yY][eE][sS]) ;;
		*) echo "Aborted. Nothing was written."; exit 0 ;;
	esac
fi

$SUDO mkdir -p "$MP/EFI"

# Copy everything in beside the old folders and verify it before touching them.
for d in $DIRS; do
	$SUDO rm -rf "$MP/EFI/$d.new"
	$SUDO cp -RX "$STAGE/EFI/$d" "$MP/EFI/$d.new"
	if ! same_tree "$STAGE/EFI/$d" "$MP/EFI/$d.new"; then
		for x in $DIRS; do $SUDO rm -rf "$MP/EFI/$x.new"; done
		echo "ABORT: EFI/$d did not copy intact. The existing EFI is untouched." >&2
		exit 1
	fi
done

for d in $DIRS; do
	$SUDO rm -rf "$MP/EFI/$d.old"
	[ -e "$MP/EFI/$d" ] && $SUDO mv "$MP/EFI/$d" "$MP/EFI/$d.old"
	$SUDO mv "$MP/EFI/$d.new" "$MP/EFI/$d"
done
for d in $DIRS; do
	$SUDO rm -rf "$MP/EFI/$d.old"
done
$SUDO find "$MP/EFI" -name '._*' -delete 2>/dev/null || true
sync

echo
echo "Verifying the installed copy..."
for d in $DIRS; do
	if ! same_tree "$STAGE/EFI/$d" "$MP/EFI/$d"; then
		echo "FAIL: EFI/$d on $DEV does not match what was staged." >&2
		[ -n "$ARCHIVE" ] && echo "Put the old one back with:  $0 --restore \"$ARCHIVE\" $DEV" >&2
		exit 1
	fi
done
"$REPO_ROOT/tools/verify-efi.sh" "$MP/EFI"

echo
if [ -n "$RESTORE" ]; then
	echo "Restored $RESTORE onto /dev/$DEV."
else
	echo "Installed OpenCore $OC_VERSION onto /dev/$DEV."
	INSTALLED=$(python3 -c "
import plistlib,sys
print(plistlib.load(open(sys.argv[1],'rb'))['PlatformInfo']['Generic']['SystemSerialNumber'])
" "$MP/EFI/OC/config.plist")
	if [ "$INSTALLED" = "$PLACEHOLDER_SERIAL" ]; then
		cat <<EOF

SMBIOS is still placeholders — iServices will not work until you run:

  ./tools/apply-smbios.sh "$MP/EFI/OC/config.plist"
EOF
	fi
fi
if [ -n "$ARCHIVE" ]; then
	echo
	echo "To undo:  $0 --restore \"$ARCHIVE\" $DEV"
fi
