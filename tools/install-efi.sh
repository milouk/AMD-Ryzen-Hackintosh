#!/bin/sh
#
# install-efi.sh — back up an EFI partition, then install this repo's EFI onto it
#
# Always backs up whatever is already there before writing, and runs verify-efi.sh
# on the result. It will not touch a partition that is not an EFI system partition.
#
# Usage:
#   ./tools/install-efi.sh --list                # show candidate EFI partitions
#   ./tools/install-efi.sh disk2s1               # back up + install onto disk2s1
#   ./tools/install-efi.sh --backup-only disk0s1 # just archive what is there now
#
# Needs sudo to mount EFI partitions.
#

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BACKUP_DIR="$REPO_ROOT/tools/.backups"
BACKUP_ONLY=0
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
		-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
		*) DEV=$1; shift ;;
	esac
done

if [ -z "$DEV" ]; then
	echo "ERROR: which EFI partition? Run '$0 --list' first." >&2
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

cleanup() {
	if [ "$MOUNTED_BY_US" -eq 1 ]; then
		sudo diskutil unmount "$DEV" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------- back it up
STAMP=$(date +%Y%m%d-%H%M%S)
if [ -d "$MP/EFI" ]; then
	mkdir -p "$BACKUP_DIR"
	ARCHIVE="$BACKUP_DIR/EFI-$DEV-$STAMP.tar.gz"
	echo "Backing up existing EFI -> $ARCHIVE"
	tar -czf "$ARCHIVE" -C "$MP" EFI
	echo "  $(du -h "$ARCHIVE" | cut -f1) archived"
else
	echo "No existing EFI folder on $DEV — nothing to back up."
fi

if [ "$BACKUP_ONLY" -eq 1 ]; then
	echo "Backup only — not writing anything. Done."
	exit 0
fi

# --------------------------------------------------- preflight the source
echo
echo "Verifying the EFI we are about to install..."
if ! "$REPO_ROOT/tools/verify-efi.sh" >/dev/null 2>&1; then
	echo "REFUSING: tools/verify-efi.sh fails on the repo EFI." >&2
	echo "Run it directly to see why. Most likely you have not run" >&2
	echo "tools/fetch-wifi-kexts.sh yet." >&2
	exit 1
fi
echo "  source EFI is complete and internally consistent"

# -------------------------------------------------------------- install
echo
printf 'Replace EFI on /dev/%s with this repo EFI? [y/N] ' "$DEV"
read -r ANSWER
case "$ANSWER" in
	[yY]|[yY][eE][sS]) ;;
	*) echo "Aborted. Nothing was written."; exit 0 ;;
esac

sudo rm -rf "$MP/EFI"
sudo cp -R "$REPO_ROOT/EFI" "$MP/EFI"

echo
echo "Verifying the installed copy..."
"$REPO_ROOT/tools/verify-efi.sh" "$MP/EFI"

cat <<EOF

Installed. Remaining manual step:

  ./tools/apply-smbios.sh "$MP/EFI/OC/config.plist"

Your SMBIOS is still placeholders until you do — iServices will not work,
and the serial needs checking at checkcoverage.apple.com.
EOF
