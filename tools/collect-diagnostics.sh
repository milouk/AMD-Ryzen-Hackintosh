#!/bin/sh
#
# collect-diagnostics.sh — read-only snapshot of the running Hackintosh
#
# Everything here only reads. It changes nothing, installs nothing, and needs no
# sudo except for two clearly-marked optional sections (EFI mount, panic logs).
#
# Run it on the Ryzentosh — on the current Catalina install before the upgrade,
# and again on Sequoia afterwards — then hand over the resulting file.
#
# Usage:  ./tools/collect-diagnostics.sh [output-file]
# Default output: ~/Desktop/ryzentosh-diagnostics-<date>.txt
#

set -u

OUT=${1:-"$HOME/Desktop/ryzentosh-diagnostics-$(date +%Y%m%d-%H%M%S).txt"}

section() {
	printf '\n\n========================================================================\n' >>"$OUT"
	printf '== %s\n' "$1" >>"$OUT"
	printf '========================================================================\n' >>"$OUT"
}

run() {
	printf '\n$ %s\n' "$*" >>"$OUT"
	"$@" >>"$OUT" 2>&1 || printf '(command unavailable or failed on this macOS version)\n' >>"$OUT"
}

: >"$OUT"
printf 'Ryzentosh diagnostics — %s\n' "$(date)" >>"$OUT"

section "macOS / kernel"
run sw_vers
run uname -a

section "SMBIOS identity (check this matches PlatformInfo > Generic)"
run system_profiler SPHardwareDataType

section "CPU"
run sysctl -n machdep.cpu.brand_string
run sysctl -n machdep.cpu.core_count
run sysctl -n machdep.cpu.thread_count
run sysctl -n hw.ncpu
# Should print 0. A 1 means something is forcing the VMM Secure Boot model.
run sysctl -n kern.hv_vmm_present

section "SIP / Secure Boot / OpenCore NVRAM"
run csrutil status
run nvram -p

section "PCI devices (source of truth for DeviceProperties paths)"
# DeviceProperties injects built-in onto the ethernet controller by PciRoot path.
# pcidebug gives bus:device:function for every PCI device, which is what that
# path is built from. gfxutil renders it directly if you have it installed:
#   gfxutil -f ethernet     https://github.com/acidanthera/gfxutil
printf '\n$ ioreg -rw0 -c IOPCIDevice  (name / location / built-in)\n' >>"$OUT"
ioreg -rw0 -c IOPCIDevice 2>/dev/null |
	grep -E '\+-o |"IOName"|"pcidebug"|"acpi-path"|"built-in"|"model"|"device-id"|"vendor-id"' \
	>>"$OUT" 2>&1 || printf '(ioreg query failed)\n' >>"$OUT"
if command -v gfxutil >/dev/null 2>&1; then
	run gfxutil -f ethernet
else
	printf '\n(gfxutil not installed — install it to print PciRoot paths directly)\n' >>"$OUT"
fi
run system_profiler SPPCIDataType

section "Network interfaces (en0 MUST be Ethernet for iServices)"
run networksetup -listallhardwareports
run ifconfig -a
run system_profiler SPEthernetDataType

section "Wi-Fi and Bluetooth"
run system_profiler SPAirPortDataType
run system_profiler SPBluetoothDataType

section "Storage — NVMe, SATA, volumes"
run diskutil list
run system_profiler SPNVMeDataType
run system_profiler SPSerialATADataType
run system_profiler SPStorageDataType
run diskutil info /

section "TRIM status (should be Yes on the macOS boot drive)"
run system_profiler SPSerialATADataType SPNVMeDataType

section "GPU / displays"
run system_profiler SPDisplaysDataType

section "Audio"
run system_profiler SPAudioDataType

section "USB tree (compare against USBPorts.kext map)"
run system_profiler SPUSBDataType

section "Loaded third-party kexts"
if command -v kmutil >/dev/null 2>&1; then
	printf '\n$ kmutil showloaded --collection auxiliary\n' >>"$OUT"
	kmutil showloaded --collection auxiliary >>"$OUT" 2>&1 ||
		printf '(needs Big Sur+; falling back to kextstat)\n' >>"$OUT"
fi
printf '\n$ kextstat | grep -v com.apple\n' >>"$OUT"
kextstat 2>/dev/null | grep -v com\\.apple >>"$OUT" 2>&1 ||
	printf '(kextstat removed on this macOS version)\n' >>"$OUT"

section "Power / sleep settings"
run pmset -g
run pmset -g assertions

section "Recent wake/sleep and panic history"
printf '\n$ pmset -g log | grep -E "Sleep|Wake|Failure" | tail -60\n' >>"$OUT"
pmset -g log 2>/dev/null | grep -E 'Sleep|Wake|Failure' | tail -60 >>"$OUT" 2>&1 ||
	printf '(no pmset log)\n' >>"$OUT"
printf '\n$ ls /Library/Logs/DiagnosticReports/*.panic\n' >>"$OUT"
ls -la /Library/Logs/DiagnosticReports/*.panic >>"$OUT" 2>&1 ||
	printf '(no panic logs — good)\n' >>"$OUT"

section "OPTIONAL — EFI partition contents (needs sudo)"
printf 'Skipped by default. To include, run:\n' >>"$OUT"
printf '  sudo diskutil mount disk0s1 && ls -laR /Volumes/EFI/EFI/OC | head -100\n' >>"$OUT"
printf '  cat /Volumes/EFI/opencore-*.txt   # OpenCore boot log, if Misc>Debug>Target writes one\n' >>"$OUT"

printf '\n\nDone.\n' >>"$OUT"

echo "Wrote $OUT"
echo
echo "Review it before sharing — it contains your machine's serial number, board"
echo "serial (MLB), hardware UUID and MAC addresses. Redact if you are posting it"
echo "anywhere public."
