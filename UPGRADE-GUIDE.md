# Upgrade Guide: Catalina (OC 0.6.3) -> Sequoia (OC 1.0.8)

Hardware: Ryzen 2700 | MSI B450M Mortar Max | RX 460 | BCM94331CD -> BCM943602CS

| | Before | After |
|---|---|---|
| macOS | Catalina 10.15.5 on Kingston A400 240GB SATA | **Sequoia 15 on Crucial P310 500GB NVMe (M2_1)** |
| Windows | ADATA XPG SX8200 Pro 256GB NVMe (M2_1) | removed from the machine |
| Bootloader | OpenCore 0.6.3, iMacPro1,1 | OpenCore 1.0.8, MacPro7,1 |
| WiFi | BCM94331CD | BCM943602CS (Phase 7, optional, later) |

**Nothing that exists today gets erased.** Sequoia is a clean install onto a
new, empty drive. The XPG comes out of the machine with Windows intact on it,
and the Kingston keeps a bootable Catalina until you decide to retire it. At
every step the way back is "pull the USB stick and reboot".

**Ethernet is required.** The installer downloads macOS over the network, and
Sequoia has no driver for any Broadcom WiFi card — not the old one, not the new
one. Plug a cable into the motherboard port for the whole upgrade.

---

## What you need

- The Crucial P310, and a screwdriver for the M.2 slot
- An ethernet cable to the router
- One USB stick, 4GB or larger (it gets erased)
- A Mac with this repo cloned, to build the stick — the Catalina install works,
  and so does any other Mac
- Optional: an external drive, if there are files on the Kingston you would be
  upset to lose to a wrong click

---

## Phase 0: Hardware

1. Shut down and unplug the power cable.
2. Remove the XPG from **M2_1** (the upper M.2 slot, by the CPU) and fit the
   P310 in its place. Put the XPG somewhere safe; it still holds Windows.
3. Leave the Kingston connected.
4. Plug in the ethernet cable.
5. Leave the WiFi card where it is.

With only M2_1 populated every PCIe slot keeps working. If a second drive ever
goes into **M2_2**, the bottom full-length slot (PCI_E4) loses its lanes and a
card in it disappears — move the WiFi card to a short x1 slot first.

---

## Phase 1: Prepare, on the current Catalina install

Boot Catalina as normal.

### 1.1 Snapshot the machine

```bash
cd /path/to/this/repo
./tools/collect-diagnostics.sh
```

A read-only report lands on the Desktop: PCI paths, which interface is `en0`,
disks, loaded kexts, SIP state, USB tree. Keep it — run it again on Sequoia and
diff the two. It contains your serial number and MAC addresses; redact before
posting it anywhere.

### 1.2 Copy off anything irreplaceable

The plan does not erase the Kingston, so this is insurance against a mistake in
Disk Utility, not a required step. Documents, pictures, SSH keys, anything that
exists only on this disk.

### 1.3 Sign out of Apple services

The machine is about to change identity (iMacPro1,1 -> MacPro7,1), so give
Apple's servers a clean break. In this order:

1. **Messages** > Preferences > iMessage > Sign Out
2. **FaceTime** > Preferences > Sign Out
3. **System Preferences** > Apple ID > Overview > Sign Out, choosing
   "Keep a Copy" when asked

### 1.4 Note the ethernet MAC address

```bash
networksetup -listallhardwareports | grep -A2 "Hardware Port: Ethernet"
```

It must be the port macOS calls Ethernet, and that port must be `en0`. This
address becomes `ROM` in the new config and is what ties iServices to the
machine.

### 1.5 BIOS settings

Restart and press **Del**. Press F7 for Advanced Mode if needed.

| Disable | Enable |
|---|---|
| Fast Boot | **Above 4G Decoding** |
| Secure Boot | XHCI Hand-off |
| CSM (or set "UEFI only") | SATA mode: AHCI |
| IOMMU | |

**Above 4G Decoding is not optional.** The old EFI worked around it being off
with `npci=0x2000`; the new one does not carry that workaround.

A-XMP is worth enabling while you are here — the RAM is a 3200MHz kit and runs
at 2400MHz without it. Note the BIOS version shown at the top of the screen.
Save with **F10**.

---

## Phase 2: Build the USB stick

One stick carries both the new bootloader and the installer. Build it on any
Mac that has this repo.

1. Plug the stick in. In **Disk Utility** choose View > Show All Devices,
   select the stick's top-level device and Erase it:
   - Name: `INSTALL`
   - Format: **MS-DOS (FAT)**
   - Scheme: **GUID Partition Map**
2. Then:

```bash
cd /path/to/this/repo
./tools/fetch-wifi-kexts.sh                 # public repo only; the private one tracks them
./tools/install-efi.sh --list               # find the stick's EFI row, e.g. disk4s1
./tools/install-efi.sh disk4s1              # verifies, validates and installs the EFI

sudo diskutil mount disk4s1
./tools/apply-smbios.sh --rom <ethernet MAC from 1.4> /Volumes/EFI/EFI/OC/config.plist

./tools/fetch-recovery.sh /Volumes/INSTALL  # ~700MB Sequoia recovery image
```

3. `apply-smbios.sh` prints a serial. Enter it at
   <https://checkcoverage.apple.com/>. You want "unable to check coverage for
   this serial number". If it shows a real Mac, run `apply-smbios.sh` again.

`fetch-recovery.sh` asks Apple for the newest macOS an iMac19,1 can run, which
is Sequoia. Asking as MacPro7,1 would return Tahoe. The image is not tied to
the SMBIOS you boot with; `--tahoe` overrides it.

If ethernet is truly impossible, the alternative is a full offline installer
made with `createinstallmedia` on a 16GB stick. You then land in a Sequoia with
no network at all until WiFi is patched, so treat it as a last resort.

---

## Phase 3: Test the new bootloader against Catalina

This boots the Catalina you already have using the new EFI from the stick.
Nothing internal is written. The AMD kernel patches are scoped by kernel
version, so only the Catalina-appropriate ones apply.

1. Put the stick in the PC and restart.
2. Tap **F11** for the boot menu and choose the **USB stick**.
   The menu also lists an entry called **OpenCore** — that is the old 0.6.3
   bootloader on the Kingston, and it is your way back to today's setup.
3. In the picker choose the Catalina disk.

Verbose text scrolls instead of the Apple logo; `-v` is in the boot-args on
purpose. Reaching the login screen means the new EFI works.

WiFi will be missing — the old card needed a kext the new EFI does not carry.
That is expected; use ethernet.

### Check once it is up

- [ ] Audio (HDMI and the rear jacks)
- [ ] Ethernet connected, and still `en0`
- [ ] Every USB port, front and back, with a USB 2 and a USB 3 device
- [ ] Smooth graphics, no glitches
- [ ] Bluetooth controller listed in System Information
- [ ] Fan speeds visible to a monitoring app (`SMCSuperIO`); if not, disable it
      in `Kernel > Add` — it is optional

### If it does not boot

Pull the stick and restart; you are back on the old EFI.

| What you see | What it means | Fix |
|---|---|---|
| Black screen, nothing loads | The stick's EFI is not being started | Check you picked the stick in F11; try a rear USB port |
| `OCABC: Incompatible OpenRuntime` | Mixed OpenCore versions | Re-run `install-efi.sh` on the stick |
| Hangs at `PCI Configuration Begin` | Above 4G Decoding is off | Enable it in the BIOS (1.5) |
| Stuck at `[EB\|#LOG:EXITBS:START]` | Memory map | Flip `SetupVirtualMap` in `config.plist` |
| Kernel panic mentioning AMD | Kernel patches not applying | Check they are enabled and the core count is `08` |
| No drives in the picker | Volumes not scanned | `ScanPolicy` must be `0`, `HfsPlus.efi` enabled |

OpenCore writes `opencore-<date>.txt` to the stick's EFI partition on each
boot. Mount it from Catalina and read the last lines — they say where it
stopped. For more detail, replace `BOOTx64.efi`, `OpenCore.efi`,
`OpenRuntime.efi` and `OpenCanopy.efi` on the stick with the ones from
`OpenCore-1.0.8-DEBUG.zip`; all four must come from the same build.

---

## Phase 4: Install Sequoia onto the P310

1. Restart, **F11**, choose the stick.
2. In the picker choose the recovery entry (it appears as a macOS recovery /
   `.dmg` entry with an external-disk icon).
3. Wait for the macOS Utilities window. Loading from USB takes a few minutes.
4. Open **Disk Utility**, View > Show All Devices.
5. Select the **Crucial** top-level device. It is the only 500GB disk; the
   Kingston is 240GB. Erase it:
   - Name: `Macintosh HD`
   - Format: **APFS**
   - Scheme: **GUID Partition Map**
6. Quit Disk Utility, choose **Reinstall macOS Sequoia**, and pick that disk.

The install reboots two or three times. Each time: F11, choose the stick, and
in the picker choose **macOS Installer**. When that entry is replaced by
**Macintosh HD**, choose that.

In the setup wizard:

- Network: ethernet connects by itself
- Migration Assistant: **Not Now** — this is a clean install
- Apple ID: **Set Up Later**; sign in after Phase 5
- Create your user account

---

## Phase 5: After the install

### 5.1 Put the bootloader on the P310

You are still booting from the stick. In Terminal on Sequoia:

```bash
diskutil list                                  # find both EFI partitions
sudo diskutil mount <the stick's EFI>          # e.g. disk4s1
ls /Volumes/EFI/EFI/OC/config.plist            # must exist: /Volumes/EFI is the stick
sudo diskutil mount <the P310's EFI>           # e.g. disk0s1
ls /Volumes                                    # the P310's shows up as "EFI 1"

sudo cp -R /Volumes/EFI/EFI "/Volumes/EFI 1/"
ls "/Volumes/EFI 1/EFI/OC/config.plist"
```

Copying from the stick, rather than from the repo, carries across the SMBIOS
you generated in Phase 2.

Remove the stick and restart. If the machine goes to the BIOS or to Catalina
instead of the picker, set the Crucial first in the BIOS boot order.

### 5.2 Reset NVRAM

At the picker press **Space** to show the hidden entries, choose
**Reset NVRAM**, and boot Sequoia again. This clears variables left by the old
bootloader and applies the new `csr-active-config`.

### 5.3 Sign in to Apple services

Check first that ethernet is `en0`:

```bash
networksetup -listallhardwareports
```

If it is not, delete
`/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist`, reboot and
check again. Then sign in under System Settings, then Messages, then FaceTime.
"Waiting for activation" can last up to a day on a new identity.

If sign-in fails outright: confirm the serial is still unknown at
checkcoverage.apple.com, wait 24 hours, and as a last resort call Apple
Support — they can reset activation on their side.

### 5.4 USB and sleep

Test every port again. The port map (`USBPorts.kext`) was retargeted to
MacPro7,1 and one half of it attaches for the first time, so this is the first
real test of it. If ports are missing, remap with
[USBToolBox](https://github.com/USBToolBox/tool) and replace `USBPorts.kext`.

Sleep was never used under Catalina (it was set to "never"), so it is untested
on this machine. Try Apple menu > Sleep and wake with the keyboard. If it wakes
immediately or not at all, the USB map is the first suspect.

### 5.5 Audio

The codec is an ALC892 and `alcid=1` is the layout that works under Catalina.
If the rear jacks are silent on Sequoia, try `alcid=` 2, 3, 7, 11 or 12 in the
boot-args. `boot-args` is under `NVRAM > Delete`, so a change takes effect on
the next boot. The 3.5mm microphone does not work with AppleALC on AMD boards;
use a USB or Bluetooth one.

### 5.6 Turn off verbose boot

Once everything is stable, remove `-v` from `boot-args` and leave the rest —
`revpatch=pci,cpuname` is what suppresses the MacPro7,1 PCI and memory
warnings. Optionally set `Misc > Debug > Target` to `3` and `AppleDebug` to
`NO` to stop writing a log to the EFI partition on every boot.

---

## Phase 6: Checklist

### Boot and system

- [ ] Sequoia boots from the P310 with the stick removed
- [ ] OpenCanopy picker shows, with mouse and keyboard working
- [ ] System Information reports MacPro7,1
- [ ] `diskutil info / | grep Protocol` reports PCI-Express
- [ ] `system_profiler SPNVMeDataType | grep -i trim` says Yes
- [ ] The P310 shows as an internal disk, not an orange external one

### Hardware

- [ ] Audio output
- [ ] Ethernet, as `en0`
- [ ] All USB ports
- [ ] GPU acceleration
- [ ] Sleep and wake, several cycles
- [ ] CPU temperature (SMCAMDProcessor) and GPU temperature (SMCRadeonSensors)
- [ ] Fan speeds (SMCSuperIO)

### Config sanity

- [ ] No PCI or memory warning in System Settings (`revpatch=pci`)
- [ ] About This Mac shows a real CPU name (`revpatch=cpuname`)
- [ ] `sysctl -n kern.hv_vmm_present` returns 0

### Apple services

- [ ] iCloud, App Store, iMessage, FaceTime

When all of that holds, the Kingston has done its job. Copy anything you still
want from it, then power off and remove it.

---

## Phase 7: The BCM943602CS and WiFi

Independent of everything above. Do it a day or a month later; the machine is
complete on ethernet in the meantime.

### 7.0 What you are up against

| macOS | Broadcom WiFi |
|---|---|
| Ventura 13 and earlier | Native |
| Sonoma 14 | Apple starts pulling the stack apart |
| **Sequoia 15** | **`IO80211FamilyLegacy.kext` is gone — no driver at all** |
| Tahoe 26 | Still gone; OCLP root patches no longer work either |

Nothing is wrong with the card and no other Broadcom card avoids this.
Bluetooth is a separate USB device and is unaffected.

The workaround has two halves:

1. **In the EFI, already configured.** `Kernel > Block` excludes Sequoia's
   `IOSkywalkFamily`; `Kernel > Add` entries 15–18 inject the Ventura stack
   (`AMFIPass`, `IOSkywalkFamily`, `IO80211FamilyLegacy` and its
   `AirPortBrcmNIC` plugin, which matches `pci14e4,43ba`, the BCM43602).
   `SecureBootModel` is `Disabled` and `csr-active-config` is `03080000`,
   because Apple Secure Boot and full SIP reject the downgraded kexts.
2. **In the installed system.** Apple also removed the matching frameworks, so
   expect to run **OpenCore Legacy Patcher** and apply
   **Post-Install Root Patch > Networking: Modern Wireless**.

**The ongoing cost:** no Apple Secure Boot, SIP partly disabled, macOS updates
arriving as full installers, and the root patch to re-apply after every update
— over ethernet, because WiFi is gone until you do.

### 7.1 Fit the card

The module normally arrives mounted on a PCIe x1 carrier with antennas. Shut
down, unplug, swap it for the BCM94331CD in the same slot, reconnect the
antennas until they click.

Keep MacPro7,1. `AirPortBrcmNIC` matches on PCI ID, not on the Mac model, and
MacPro7,1 being IGPU-free is what gives full DRM with an AMD card.

### 7.2 Boot and test

1. Reset NVRAM once, then boot Sequoia.
2. Check what loaded:

```bash
system_profiler SPAirPortDataType
kmutil showloaded --collection auxiliary | grep -iE "80211|Skywalk|BrcmNIC"
csrutil status        # partially disabled is expected
```

3. If the card is detected but no networks appear, apply the OCLP root patch
   and reboot.

**If WiFi works but misbehaves** (no 5GHz, wrong region, drops after wake), add
[AirportBrcmFixup](https://github.com/acidanthera/AirportBrcmFixup) as a Lilu
plugin: `brcmfx-country=US` sets the region, `brcmfx-delay=15000` fixes
start-up races, `brcmfx-aspm=0` fixes drops after sleep.

**If Bluetooth is missing**, check `BlueToolFixup.kext` is enabled and reset
NVRAM.

### 7.3 Backing the WiFi patch out

If the trade is not worth it, revert these and reset NVRAM. You keep Bluetooth
and run on ethernet with stock security.

| Setting | Patched | Revert to |
|---|---|---|
| `Kernel > Add` entries 15–18 | Enabled | Disabled |
| `Kernel > Block` IOSkywalkFamily | Enabled | Disabled |
| `Misc > Security > SecureBootModel` | `Disabled` | `Default` |
| `NVRAM > csr-active-config` | `03080000` | `00000000` |

The other route is an Intel AX210 with `AirportItlwm`: WiFi with SIP and Secure
Boot intact, at the cost of unreliable AirDrop, Handoff and Continuity.

---

## Debugging with Claude Code

Claude can read OpenCore logs, panic reports and the config directly, which is
faster than searching forums for an error string.

```bash
# Boot log from the EFI partition
sudo diskutil mount disk0s1
claude "diagnose this opencore boot log" < /Volumes/EFI/opencore-*.txt

# The config
claude "audit this OC 1.0.8 config for an AMD Ryzen 2700 + RX 460" < /Volumes/EFI/EFI/OC/config.plist

# A kernel panic
claude "explain this hackintosh kernel panic" < /Library/Logs/DiagnosticReports/*.panic
```

- **Nothing boots:** photograph the screen where it stops and upload it at
  claude.ai with the hardware, the OpenCore version and the macOS version.
- **Another Mac is available:** move the stick over, mount its EFI partition
  and feed `opencore-*.txt` to Claude there.
- Run Claude from this repo directory and it already has the config, this
  guide and the tools as context.

---

## Emergency recovery

**The new EFI does not boot.** Pull the stick and restart. The Kingston still
has the old bootloader and Catalina.

**Sequoia installed but will not boot from the P310.** Boot from the stick and
choose Macintosh HD. If that works, the EFI on the P310 is the problem — redo
5.1. If it does not, read the verbose output for where it stops.

**Back to Catalina at any point.** F11 and choose the Kingston (or the
"OpenCore" entry). Sign back in to Apple services there if you stay.

**iServices will not activate.** Generate a fresh identity with
`tools/apply-smbios.sh`, reset NVRAM, and sign in again. A "Customer Code"
error means calling Apple Support.

**The P310 misbehaves under macOS.** It is a DRAM-less drive and macOS support
for its Host Memory Buffer is unclear. If sleep, wake or sustained writes are a
problem, the XPG is the better-built drive and can take its place.
