#!/bin/sh
#
# verify-efi.sh — cross-check config.plist against what is actually on disk
#
# ocvalidate checks the config against OpenCore's schema. It does not know
# whether the kexts, SSDTs, drivers and tools the config references exist.
# This does. Run it before copying EFI/ anywhere.
#
# Usage:  ./tools/verify-efi.sh [path-to-EFI-dir]
# Default: the EFI/ directory in this repository
#

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
EFI_DIR=${1:-"$REPO_ROOT/EFI"}

if [ ! -f "$EFI_DIR/OC/config.plist" ]; then
	echo "ERROR: no config.plist at $EFI_DIR/OC/config.plist" >&2
	exit 1
fi

python3 - "$EFI_DIR" <<'PY'
import os, plistlib, sys

efi = sys.argv[1]
oc = os.path.join(efi, "OC")
cfg = plistlib.load(open(os.path.join(oc, "config.plist"), "rb"))

problems, warnings, checked = [], [], 0

def exists(rel, what):
    global checked
    checked += 1
    if not os.path.exists(os.path.join(oc, rel)):
        problems.append(f"{what}: missing {rel}")
        return False
    return True

# --- ACPI --------------------------------------------------------------
for e in cfg["ACPI"]["Add"]:
    if e.get("Enabled"):
        exists(os.path.join("ACPI", e["Path"]), "ACPI")

# --- Kexts -------------------------------------------------------------
enabled_kexts = []
for e in cfg["Kernel"]["Add"]:
    if not e.get("Enabled"):
        continue
    bundle = e["BundlePath"]
    enabled_kexts.append(bundle)
    base = os.path.join("Kexts", bundle)
    if not exists(base, "Kext"):
        continue
    for key, label in (("PlistPath", "Info.plist"), ("ExecutablePath", "executable")):
        sub = e.get(key) or ""
        if sub:
            exists(os.path.join(base, sub), f"Kext {bundle} {label}")

# --- Drivers and Tools -------------------------------------------------
for e in cfg["UEFI"]["Drivers"]:
    if e.get("Enabled"):
        exists(os.path.join("Drivers", e["Path"]), "Driver")
for e in cfg["Misc"]["Tools"]:
    if e.get("Enabled"):
        exists(os.path.join("Tools", e["Path"]), "Tool")

# --- Bootloader itself -------------------------------------------------
exists("OpenCore.efi", "Bootloader")
checked += 1
if not os.path.exists(os.path.join(efi, "BOOT", "BOOTx64.efi")):
    problems.append("Bootloader: missing BOOT/BOOTx64.efi")

# --- OpenCanopy theme --------------------------------------------------
boot = cfg["Misc"]["Boot"]
if boot.get("PickerMode") == "External":
    variant = (boot.get("PickerVariant") or "").replace("\\", os.sep)
    if variant and variant != "Auto":
        exists(os.path.join("Resources", "Image", variant), "PickerVariant")

# --- Cross-checks that catch the specific footguns in this EFI ---------
blocked = {b["Identifier"] for b in cfg["Kernel"]["Block"] if b.get("Enabled")}
if "com.apple.iokit.IOSkywalkFamily" in blocked:
    need = ["IOSkywalkFamily.kext", "IO80211FamilyLegacy.kext",
            "IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext"]
    missing = [n for n in need if n not in enabled_kexts]
    if missing:
        problems.append(
            "WiFi: IOSkywalkFamily is blocked but these replacements are not "
            "injected: " + ", ".join(missing) +
            " -- you will have no WiFi. Run ./tools/fetch-wifi-kexts.sh, or "
            "disable the block.")
    if cfg["Misc"]["Security"]["SecureBootModel"] != "Disabled":
        problems.append(
            "WiFi: the WiFi patch needs Misc>Security>SecureBootModel = Disabled, "
            f"found {cfg['Misc']['Security']['SecureBootModel']!r}")
    csr = cfg["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"].get(
        "csr-active-config", b"")
    if csr == b"\x00\x00\x00\x00":
        problems.append(
            "WiFi: csr-active-config is 00000000 (SIP fully on); the injected "
            "kexts will be rejected. Expected 03080000.")

nvram_delete = cfg["NVRAM"]["Delete"].get(
    "7C436110-AB2A-4BBB-A880-FE41995C9F82", [])
for var in ("boot-args", "csr-active-config"):
    if var in cfg["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"] \
       and var not in nvram_delete:
        warnings.append(
            f"NVRAM: {var} is in Add but not Delete -- changes to it will be "
            "ignored once the variable exists in NVRAM")

# SMCAMDProcessor reads sensor data collected by AMDRyzenCPUPowerManagement.
if "SMCAMDProcessor.kext" in enabled_kexts and \
   "AMDRyzenCPUPowerManagement.kext" in enabled_kexts:
    if enabled_kexts.index("AMDRyzenCPUPowerManagement.kext") > \
       enabled_kexts.index("SMCAMDProcessor.kext"):
        problems.append(
            "Kext order: AMDRyzenCPUPowerManagement must load before "
            "SMCAMDProcessor")

if enabled_kexts and enabled_kexts[0] != "Lilu.kext":
    problems.append(f"Kext order: Lilu must load first, found {enabled_kexts[0]}")

# --- Report ------------------------------------------------------------
print(f"Checked {checked} referenced paths across "
      f"{len(enabled_kexts)} enabled kexts.\n")

for w in warnings:
    print(f"  WARN   {w}")
for p in problems:
    print(f"  FAIL   {p}")

if problems:
    print(f"\n{len(problems)} problem(s) found.")
    sys.exit(1)

print("  OK     every enabled kext, SSDT, driver and tool is present")
print("  OK     WiFi patch is internally consistent")
print("  OK     kext load order is sane")
if warnings:
    print(f"\nPassed with {len(warnings)} warning(s).")
else:
    print("\nAll good.")
PY
