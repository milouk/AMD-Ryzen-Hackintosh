# Upgrade Guide: Catalina (OC 0.6.3) -> Sequoia (OC 1.0.7)

Hardware: Ryzen 2700 | MSI B450M Mortar Max | RX 460 | BCM94331CD -> BCM943602CS

**Both OSes move to NVMe.** The clean install in Phase 5 is the right moment.
See Phase 5.3.

| | Before | After |
|---|---|---|
| macOS | Kingston A400 256GB SATA | **XPG SX8200 Pro 256GB NVMe — M2_1** |
| Windows | XPG NVMe | **Crucial P310 500GB NVMe — M2_2** |
| Kingston A400 SATA | macOS | spare / data / scratch |

**Why macOS gets the smaller drive.** These two are not close in build quality:

| | XPG SX8200 Pro 256GB | Crucial P310 500GB |
|---|---|---|
| Controller | SMI SM2262EN | Phison PS5027-E27T |
| DRAM cache | **Yes** | **No** — relies on HMB |
| NAND | TLC | **QLC** (on the 500GB specifically) |
| Interface | PCIe 3.0 x4 | PCIe 4.0 x4 |

TLC with a real DRAM cache is the better boot drive, full stop. QLC has weaker
sustained write performance once the SLC cache fills, and lower endurance.

On top of that, the P310 leans on **HMB** (Host Memory Buffer) to keep its
flash translation table in system RAM in place of an onboard DRAM chip.
Windows implements HMB; macOS's support is at best unclear — `NVMeFix`
certainly does not add it, as its feature list is APST, host-driven power
management and timeout-panic workarounds, nothing more. So the P310 is likely
running without its performance crutch under macOS and with full benefit under
Windows. Even if macOS turns out to handle HMB fine, the TLC-plus-DRAM drive
still wins for a boot volume.

256GB is what you are running today, so this is no regression in capacity.

The P310 being Gen4 buys nothing here either way: M2_1 is PCIe 3.0 x4 and
M2_2 is PCIe 2.0 x4, so a 7,100 MB/s drive is capped well below its rating in
either slot. It will still comfortably outrun the SATA A400 it replaces.

**You can do this entire upgrade on ethernet only.** The WiFi card swap
(BCM94331CD -> BCM943602CS) is completely independent — do it whenever.
Use wired ethernet throughout. The guide marks WiFi steps as optional.

### Read this before you count on WiFi

Apple removed `IO80211FamilyLegacy.kext` in macOS Sequoia. That kext *was* the
driver for every Broadcom WiFi card, so **the BCM943602CS gets no WiFi out of
the box on Sequoia**, the same as a BCM94360CD or a Fenvi T919 would not. The
card is fine; the driver is missing from the OS.

This EFI works around it by blocking Sequoia's `IOSkywalkFamily` and injecting
the Ventura networking stack in its place. That costs you Apple Secure Boot and
full SIP, and it may need re-patching after macOS updates. Bluetooth is
unaffected and works natively via BlueToolFixup. Phase 8 covers the whole thing.

---

## What you need before starting

- **USB Drive #1** (4GB+): Your new EFI "test stick" — this is how you test
  the new OpenCore without risking your working install
- **USB Drive #2** (16GB+): The macOS Sequoia installer
- **External drive** (recommended): For Time Machine backup — and **required**
  this time, because the drive swap erases the XPG NVMe that Windows lives on
- **Ethernet cable**: Plugged into your motherboard's Realtek port
- **BCM943602CS WiFi card** (optional, install whenever): To replace the BCM94331CD
- **Windows installer USB**: You will reinstall Windows onto the Crucial NVMe
- The new EFI folder from this repo, with `./tools/fetch-wifi-kexts.sh` already run

---

## Phase 0: Snapshot the machine you have

Before changing anything, capture what currently works. This gives you a
before/after reference, and it is the fastest way to get help if something
breaks later.

```bash
cd /path/to/AMD-Ryzen-Hackintosh
./tools/collect-diagnostics.sh
```

It writes a read-only report to your Desktop: PCI paths, which interface is
`en0`, disk layout, loaded kexts, SIP state, USB tree, audio, sensors. It
changes nothing. Keep the file — run it again after the upgrade and diff the two.

The report contains your serial number, MLB and MAC addresses. Redact before
posting it anywhere public.

---

## Phase 1: Preparation (on your current Catalina install)

Boot into your current working Catalina as normal.

### 1.1 Back up your data

Even though a clean install means you'll erase the macOS drive, you want your
files backed up so you can restore them afterwards.

**Option A: Time Machine (recommended)**
1. Plug in an external hard drive
2. Open **System Preferences** > **Time Machine**
3. Click **Select Backup Disk** and choose your external drive
4. Click **Use Disk**
5. Time Machine will start backing up. Wait for it to finish.
   First backup can take hours depending on how much data you have.

**Option B: Manual copy**
1. Open Finder
2. Copy these folders to an external drive:
   - `~/Documents`
   - `~/Desktop`
   - `~/Downloads`
   - `~/Pictures`
   - `~/Music`
   - Any other folders with your data
3. Also export your browser bookmarks, save any app-specific configs, etc.

**Back up your current working EFI** (so you can always go back):
```bash
# Open Terminal.app

# First, find which disk is your macOS drive
diskutil list
# Look for "EFI" partition on your macOS disk. It's usually disk0s1.

# Mount the EFI partition
sudo diskutil mount disk0s1

# Copy your entire working EFI to the desktop
cp -R /Volumes/EFI/EFI ~/Desktop/EFI-backup-catalina

# Verify it copied
ls ~/Desktop/EFI-backup-catalina/
# Should show: BOOT  OC
```

Also copy this backup EFI to your external drive for safekeeping.

### 1.2 Sign out of Apple services

This is CRITICAL. You're about to change your SMBIOS (the fake Mac identity),
so Apple's servers need a clean break. Do these in ORDER:

1. Open **Messages** app
   - Go to menu: **Messages** > **Preferences** > **iMessage** tab
   - Click **Sign Out**
   - Close Messages

2. Open **FaceTime** app
   - Go to menu: **FaceTime** > **Preferences**
   - Click **Sign Out**
   - Close FaceTime

3. Open **System Preferences** > **Apple ID**
   - Click **Overview** in the sidebar
   - Click **Sign Out** at the bottom
   - When asked "Keep a copy of your iCloud data on this Mac?" — click **Keep a Copy**
   - Enter your Apple ID password to turn off Find My Mac
   - Wait for sign-out to complete

### 1.3 Write down your ethernet MAC address

You need this for the ROM value in your SMBIOS config. This helps iServices
work properly after the upgrade.

```bash
# In Terminal:
ifconfig en0 | grep ether

# You'll see something like:
#   ether a4:b1:c2:d3:e4:f5
#
# Write this down! The entire address including colons.
```

### 1.4 Configure BIOS settings

1. Power on and press **Delete** key repeatedly to enter BIOS
   (MSI boards use Del, not F2)
2. Navigate to the settings below. On MSI boards, you may need to enter
   **Advanced Mode** (F7) first.

**Find and DISABLE these:**
- Fast Boot (usually under Boot or Settings > Boot)
- Secure Boot (under Settings > Security or Boot)
- CSM / Compatibility Support Module (under Boot)
  - If you can't find CSM, look for "UEFI/Legacy Boot" and set to "UEFI Only"
- IOMMU (under AMD CBS or Advanced > AMD)

**Find and ENABLE these:**
- Above 4G Decoding (under Settings > Advanced > PCI or AMD CBS)
  - This is important — it replaces the old `npci=0x2000` boot arg
- EHCI/XHCI Hand-off (under Settings > Advanced > USB)
- SATA Mode: AHCI (under Settings > Advanced > Storage)
  - This should already be AHCI if you were running macOS before

3. Press **F10** to Save and Exit

---

## Phase 2: Prepare USB #1 — the new EFI test stick

You'll test the new EFI by booting from a USB first. This way your hard
drive's working EFI stays untouched. If something goes wrong, just pull
out the USB and boot normally.

### 2.1 Boot back into Catalina

Boot into your current Catalina install using the old EFI (it's still on
your hard drive, untouched).

### 2.2 Format USB #1

1. Plug in USB #1 (the small one, 4GB+)
2. Open **Disk Utility** (Spotlight search or Applications > Utilities)
3. In the top-left, click **View** > **Show All Devices**
   (important — you need to see the physical disk, not just partitions)
4. Select the USB drive's **root device** (e.g., "SanDisk Ultra", NOT the
   indented partition underneath it)
5. Click **Erase** with these settings:
   - Name: `EFI-Test`
   - Format: **Mac OS Extended (Journaled)**
   - Scheme: **GUID Partition Map**
6. Click **Erase** and wait for it to finish

This creates a hidden EFI partition on the USB that OpenCore will live on.

### 2.3 Mount the USB's hidden EFI partition

```bash
# In Terminal, find your USB disk number:
diskutil list

# Look for your USB (named "EFI-Test"). It will be something like /dev/disk2.
# The EFI partition will be listed as disk2s1 (or disk3s1, etc.)

# Mount it:
sudo diskutil mount disk2s1
# You should see: Volume EFI on disk2s1 mounted

# It's now accessible at /Volumes/EFI
```

### 2.4 Fetch the WiFi kexts, then copy the EFI to the USB

Two of the three Broadcom restoration kexts are Apple binaries, so they are not
committed to this repo. Pull them first — `config.plist` blocks Sequoia's
`IOSkywalkFamily` on the assumption they are there:

```bash
cd /path/to/AMD-Ryzen-Hackintosh
./tools/fetch-wifi-kexts.sh
# Ends with four OK lines. If any say MISS, stop and fix it before copying.
```

```bash
# Copy the entire EFI folder from this repo to the USB's EFI partition
cp -R /path/to/AMD-Ryzen-Hackintosh/EFI /Volumes/EFI/

# Verify the structure is correct:
ls /Volumes/EFI/EFI/
# Should show: BOOT  OC

ls /Volumes/EFI/EFI/OC/
# Should show: ACPI  Drivers  Kexts  OpenCore.efi  Resources  Tools  config.plist

# And the WiFi kexts made it across:
ls /Volumes/EFI/EFI/OC/Kexts/ | grep -E "AMFIPass|IOSkywalk|IO80211"
# Should show: AMFIPass.kext  IO80211FamilyLegacy.kext  IOSkywalkFamily.kext
```

### 2.5 Generate YOUR unique SMBIOS values

The config.plist has pre-generated SMBIOS values, but you should generate
your own unique set, especially for iServices to work.

```bash
# Download GenSMBIOS
cd ~/Desktop
git clone https://github.com/corpnewt/GenSMBIOS.git
cd GenSMBIOS

# Run it
python3 GenSMBIOS.command
```

In the GenSMBIOS menu:
1. Type `1` and press Enter — this downloads MacSerial
2. Type `3` and press Enter — this generates SMBIOS
3. Type `MacPro7,1` and press Enter
4. It outputs something like:
   ```
     #######################################################
     #              MacPro7,1 SMBIOS Info                   #
     #######################################################

     Type:         MacPro7,1
     Serial:       F5KH002WP7QM
     Board Serial: F5K9104024NJG36FB
     SmUUID:       7B8A45C1-3F82-4E53-9B89-2A7B1E4F6D3E
     Apple ROM:    58A6B10D4C7F
   ```
5. **Write down ALL of these values**

Now edit the config.plist. The easiest way is with ProperTree:

```bash
# Download ProperTree
cd ~/Desktop
git clone https://github.com/corpnewt/ProperTree.git
cd ProperTree
python3 ProperTree.command
```

In ProperTree:
1. **File** > **Open** > navigate to `/Volumes/EFI/EFI/OC/config.plist`
2. Navigate to **PlatformInfo** > **Generic**
3. Set these values from GenSMBIOS output:
   - `SystemSerialNumber` = the **Serial** value
   - `MLB` = the **Board Serial** value
   - `SystemUUID` = the **SmUUID** value
4. For **ROM**: use your real ethernet MAC address (from step 1.3)
   - Remove the colons: `a4:b1:c2:d3:e4:f5` becomes `a4b1c2d3e4f5`
   - In ProperTree, click the ROM value, set type to **Data**,
     enter your MAC without colons
5. **File** > **Save**

### 2.6 Verify the serial is invalid

This is important — if your serial matches a real Mac, iServices won't work.

1. Open a browser and go to: https://checkcoverage.apple.com/
2. Enter your **SystemSerialNumber** (the Serial from GenSMBIOS)
3. Complete the CAPTCHA

**Expected result:** "We're sorry, we're unable to check coverage for this
serial number."

This means the serial is NOT registered to a real Mac. **This is what you want.**

If it shows "Valid Purchase Date" or any real Mac info, go back to GenSMBIOS
and generate a new set. Repeat until you get an invalid one.

### 2.7 Validate the config (optional but recommended)

```bash
# ocvalidate ships in the OpenCore release package, and its version must match
# the OpenCore.efi you are running — use the one from OpenCore-1.0.7-RELEASE.zip.
chmod +x /path/to/Utilities/ocvalidate/ocvalidate
/path/to/Utilities/ocvalidate/ocvalidate /Volumes/EFI/EFI/OC/config.plist

# Expected: "Completed validating ... No issues found."
```

ocvalidate only checks the config against the schema — it does not know whether
the kexts, SSDTs and drivers it references actually exist. That is what
`verify-efi.sh` is for:

```bash
cd /path/to/AMD-Ryzen-Hackintosh
./tools/verify-efi.sh /Volumes/EFI/EFI
```

It walks every enabled entry in the config, confirms the file is really there,
and flags the combinations that boot into a broken state — most importantly a
blocked `IOSkywalkFamily` with no replacement kexts, or the WiFi patch enabled
while Secure Boot and SIP are still locked down. Exit code 0 means go.

---

## Phase 3: Test the new EFI on your existing Catalina

This is the safety test. You boot your EXISTING Catalina install using
the NEW EFI from the USB. If it works, you know the EFI is good before
you touch anything.

The new EFI is fully compatible with Catalina — the AMD kernel patches
use kernel version ranges, so only the Catalina-appropriate patches
activate. Newer patches (Monterey+, Sequoia+) are automatically skipped.

### 3.1 Boot from USB #1

1. Restart the computer
2. Press **F11** repeatedly during POST (MSI boot menu key)
   - You'll see a boot menu listing all bootable devices
3. Select your USB drive (it will show the USB's brand name)
4. The BsxM1 OpenCanopy picker should appear with a nice GUI
5. Select your **macOS Catalina** drive (it will show as "macOS" or your
   drive name with a hard drive icon)
6. Press Enter

### 3.2 What you'll see during boot

Because we have `-v` (verbose mode) in boot-args, you'll see scrolling
white text on a black screen instead of the Apple logo. This is normal
and expected — it helps diagnose issues.

You'll see things like:
```
OC: Starting OpenCore...
OC: Loaded configuration of XXXX bytes
...lots of text...
Darwin Kernel Version 19.6.0...
```

If it reaches the login screen, the new EFI works on Catalina.

### 3.3 If boot fails — how to debug

**If you get a black screen and nothing happens:**
The EFI isn't loading at all.
- Re-check the folder structure on the USB: `EFI/BOOT/BOOTx64.efi` and
  `EFI/OC/OpenCore.efi` must exist
- Try a different USB port (use a rear motherboard port, not front panel)
- Make sure you selected the correct device in the F11 boot menu

**If OpenCanopy loads but selecting macOS reboots or hangs:**
1. Pull out the USB, boot normally into Catalina using your old EFI
2. Mount the USB's EFI and check for a log file:
   ```bash
   sudo diskutil mount disk2s1
   ls /Volumes/EFI/
   # Look for opencore-YYYY-MM-DD-HHMMSS.txt
   cat /Volumes/EFI/opencore-*.txt | tail -50
   ```
   The last lines before the hang tell you what went wrong.

3. For more detail, swap to OpenCore **DEBUG** build:
   - Download `OpenCore-1.0.7-DEBUG.zip` from the same GitHub releases page
   - Replace ONLY these files on the USB:
     - `EFI/BOOT/BOOTx64.efi`
     - `EFI/OC/OpenCore.efi`
     - `EFI/OC/Drivers/OpenRuntime.efi`
     - `EFI/OC/Drivers/OpenCanopy.efi`
   - All 4 MUST come from the same DEBUG build
   - Boot again — you'll see much more detailed text on screen

**Common boot failures and fixes:**

| What you see | What it means | Fix |
|---|---|---|
| `OCABC: Incompatible OpenRuntime` | OC files are from different versions | Re-download and replace all 4 OC files from same build |
| Stuck at `[EB\|#LOG:EXITBS:START]` | Memory mapping issue | Try flipping `SetupVirtualMap` (true<>false) in config.plist |
| Kernel panic mentioning AMD | Kernel patches aren't applying | Verify patches are enabled, check core count is 08 |
| No drives in picker | Can't find boot volumes | Check `ScanPolicy` is `0`, check HfsPlus.efi is enabled |
| Reboot loop (restarts immediately) | USB port limit issue | Verify `XhciPortLimit` is `NO` |

### 3.4 Once Catalina boots — test everything

Walk through this checklist:

- [ ] **Audio**: Play a YouTube video or system sound. Test both speakers
      and headphone jack.
- [ ] **Ethernet**: Open System Preferences > Network. Is Ethernet connected?
      Open Safari and load a website.
- [ ] **WiFi**: Skip. The BCM94331CD is dead on anything modern, and the
      restoration kexts are scoped to `MinKernel 23.0.0` so they stay inert on
      Catalina anyway. Phase 8 handles WiFi.
- [ ] **Bluetooth**: Skip for now if still using old card. Will work with
      BCM943602CS + BlueToolFixup (already in your EFI).
- [ ] **USB**: Plug a USB device into each port (front and back). Do they
      all show up in System Information > USB?
- [ ] **GPU**: Is the desktop smooth? Open Mission Control (F3 or swipe up
      with 4 fingers). Are animations fluid with no glitches?
- [ ] **Sleep/Wake**: Apple menu > Sleep. Wait 10 seconds, then press a key
      or move the mouse. Does it wake up?
- [ ] **Windows**: Restart, and in the OpenCanopy picker, select Windows.
      Does Windows boot? Can you get back to macOS by restarting and
      selecting macOS in the picker?

If everything works, you're ready for Phase 4.

If something doesn't work, pull out the USB and boot with your old EFI
to get back to a working state while you troubleshoot.

---

## Phase 4: Create the macOS Sequoia installer

### 4.0 The no-USB route — recommended

You do not need a USB stick for any of this. The USB was never really about the
installer; it was about having a *bootable OpenCore that isn't your working one*.
Both halves can live on internal disks:

| Piece | Where it can go |
|---|---|
| OpenCore EFI | any disk's EFI system partition, chosen at boot with **F11** |
| Installer media | any volume OpenCore can see — `ScanPolicy` is `0`, so it scans everything |

Putting the new EFI on a **different disk's** ESP gives you exactly the safety
the USB gave you: your working Catalina EFI is never touched, and if the new one
misbehaves you just pick the old disk in the F11 menu.

```bash
# 1. Put the new EFI on a spare disk's ESP (backs up whatever is there first)
./tools/install-efi.sh --list
./tools/install-efi.sh diskXs1

# 2. Fill in SMBIOS — reads your real ethernet MAC for ROM automatically
./tools/apply-smbios.sh /Volumes/EFI/EFI/OC/config.plist

# 3. Download the installer — ~700MB, not 15GB
./tools/fetch-recovery.sh /Volumes/SomeVolume
```

`fetch-recovery.sh` pulls Apple's recovery image rather than the full installer
app. OpenCore's picker boots it, and "Reinstall macOS" streams the rest over
ethernet during the install. That sidesteps two problems at once: the 15GB
download, and the fact that running Sequoia's `createinstallmedia` binary on a
host as old as Catalina is not reliably supported.

> **One detail worth knowing.** macrecovery asks Apple "what is the newest macOS
> for this Mac". MacPro7,1 is still supported by Tahoe 26, so asking as MacPro7,1
> gets you Tahoe. The script therefore asks as **iMac19,1**, which tops out at
> Sequoia 15.7.4. The recovery image is not tied to the SMBIOS you boot with, so
> this is purely a way of naming the version you want. `--tahoe` overrides it.

**You can run this from any machine.** macrecovery is plain Python over HTTP — it
does not use `createinstallmedia`, does not care what OS or CPU it runs on, and
produces a folder you copy anywhere. So download it on whatever box is most
convenient (an Apple Silicon Mac, another PC, the Catalina install itself) and
move `com.apple.recovery.boot` across:

```bash
# on any machine
./tools/fetch-recovery.sh
# then copy tools/.cache/recovery/com.apple.recovery.boot/ to the target volume root
```

That portability is the main reason to prefer it over the USB route here. The
`createinstallmedia` path needs a macOS host new enough to run the Sequoia
installer's own binary, which Catalina is not reliably, and its output is
awkward to produce from an Apple Silicon Mac for an Intel target.

**Still keep one USB stick.** Not for installing — as a rescue. Put your Catalina
EFI backup on it (`./tools/install-efi.sh --backup-only disk0s1` archives the
current one). If you end up unable to boot anything internal, that stick is the
difference between ten minutes and a very long evening.

The rest of Phase 4 is the traditional USB route. Use it if you would rather have
a fully offline installer, or if the recovery route gives you trouble.

### 4.1 Download the Sequoia installer

Catalina's `softwareupdate` may not list Sequoia. Use the installinstallmacos
script instead:

```bash
# In Terminal:
mkdir -p ~/macOS-installer
cd ~/macOS-installer

# Download the script
curl -O https://raw.githubusercontent.com/munki/macadmin-scripts/main/installinstallmacos.py

# Run it (this may take a while to fetch the catalog)
sudo python3 installinstallmacos.py
```

You'll see a numbered list of macOS versions:
```
 1. macOS Sequoia 15.3.2 [MZT62-25832]  - 15.3.2
 2. macOS Sonoma 14.7.4 [MZT42-74523]   - 14.7.4
 ...
```

Type the number for **macOS Sequoia** (latest 15.x) and press Enter.

It downloads a ~13GB DMG file. Wait for it to finish.

When done:
```bash
# Mount the downloaded DMG
hdiutil attach ~/macOS-installer/Install_macOS_*.dmg

# Move the installer to Applications
sudo mv "/Volumes/Install macOS Sequoia/Install macOS Sequoia.app" /Applications/

# Unmount the DMG
hdiutil detach "/Volumes/Install macOS Sequoia"
```

Verify:
```bash
ls /Applications/ | grep Sequoia
# Should show: Install macOS Sequoia.app
```

### 4.2 Format USB #2 (the installer USB)

1. Plug in USB #2 (the big one, 16GB+)
2. Open **Disk Utility**
3. **View** > **Show All Devices**
4. Select the USB's **root device** (the physical disk, not a partition)
5. Click **Erase**:
   - Name: `Install`
   - Format: **Mac OS Extended (Journaled)**
   - Scheme: **GUID Partition Map**
6. Click **Erase** and wait

### 4.3 Write the Sequoia installer to USB #2

```bash
# This takes 20-40 minutes. The terminal will appear frozen — that's normal.
sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia --volume /Volumes/Install

# When prompted, type Y and press Enter to confirm erasing the USB
# Wait for "Install media now available at /Volumes/Install macOS Sequoia"
```

### 4.4 Copy the new EFI to the installer USB

The installer USB needs the OpenCore EFI too, so it can boot on your AMD system.

```bash
# Mount the installer USB's hidden EFI partition
# First find the disk number:
diskutil list
# Find the USB with "Install macOS Sequoia" — note its disk number (e.g., disk3)

sudo diskutil mount disk3s1
# "Volume EFI on disk3s1 mounted"

# Copy the same EFI you already tested on USB #1
# (Mount USB #1's EFI if not already mounted)
sudo diskutil mount disk2s1

# Copy
cp -R /Volumes/EFI/EFI /Volumes/EFI\ 1/
# Note: if both EFI partitions are mounted, the second one may appear as "EFI 1"
# Adjust the path if needed. Use: ls /Volumes/ to see what's mounted.

# Verify:
ls /Volumes/EFI\ 1/EFI/OC/
# Should show: ACPI  Drivers  Kexts  OpenCore.efi  Resources  Tools  config.plist
```

---

## Phase 5: Clean install macOS Sequoia

A clean install is recommended when jumping 6 major versions (Catalina -> Sequoia).
In-place upgrades across this many versions often fail or leave a messy system.

**Your Windows NVMe will NOT be touched.** The macOS installer only writes to
the drive you explicitly select.

### 5.1 Boot from the Sequoia installer USB

1. Make sure USB #2 (installer) is plugged in. USB #1 can be unplugged now.
2. Restart the computer
3. Press **F11** during POST for the boot menu
4. Select the **installer USB** (not your internal drive)
5. The OpenCanopy picker appears
6. You'll see a new entry: **"Install macOS Sequoia"** (or similar, with
   an external drive icon)
7. Select it and press Enter

### 5.2 Boot into the Sequoia installer environment

- You'll see verbose text scrolling (because of `-v`)
- This takes several minutes — the installer is loading from USB which is slow
- Eventually you'll reach the **macOS Utilities** window with options like:
  - Restore From Time Machine Backup
  - Install macOS Sequoia
  - Disk Utility
  - Terminal

### 5.3 Erase and install — choose your target drive

**BE VERY CAREFUL HERE — identify each drive correctly!**

Your current drive layout:
- **Kingston A400 256GB** (SATA SSD) — currently has macOS Catalina
- **XPG SX8200 Pro 256GB** (NVMe) — currently has Windows
- **Crucial P310 500GB** (NVMe, M.2 2280)

Target layout: **macOS on the XPG (M2_1), Windows on the Crucial (M2_2),
Kingston freed up.** The XPG gets erased, so:

> **Back up Windows first.** The XPG is erased in this step and there is no
> undo. Copy anything you care about off the Windows partition before you
> boot the installer. Product keys for Windows are tied to the motherboard on
> a digital licence, so reactivation is usually automatic — but note any
> application licences that are tied to the machine.

**Why the XPG and not the bigger Crucial:** see the note at the top of this
guide — macOS has no HMB support, so the DRAM-less Crucial loses its
performance crutch under macOS while Windows uses it fully. Either way both
OSes gain native NVMe TRIM, so the `ThirdPartyDrives` quirk a third-party SATA
SSD needs is no longer relevant. `NVMeFix.kext` is already enabled in this EFI
and handles NVMe power management so sleep/wake stays reliable.

**Steps:**

1. Click **Disk Utility** and click Continue
2. In Disk Utility, click **View** > **Show All Devices** (top-left dropdown)
3. In the left sidebar, you'll see all your drives:
   - **XPG** or **ADATA** — the 256GB NVMe (currently Windows) — **this is the target**
   - **CT500P3...** / **Crucial** — the 512GB NVMe
   - **KINGSTON** — the 256GB SATA (currently macOS Catalina)
   - The USB installer
4. **Select the XPG's ROOT device** — the physical disk name, not a partition
   indented under it. The XPG and the Kingston are both 256GB, so confirm by
   model name, not capacity.
5. Click **Erase** with these settings:
   - Name: `Macintosh HD` (or whatever you prefer)
   - Format: **APFS**
   - Scheme: **GUID Partition Map**
6. Click **Erase**
7. Wait for it to finish, then close Disk Utility

After Sequoia is fully set up, reinstall Windows on the Crucial NVMe:
1. Create a Windows USB installer (use Microsoft's Media Creation Tool from
   another PC — do this **before** you erase the NVMe, not after)
2. Boot from the Windows USB
3. Install Windows on the Crucial NVMe (M2_2)
4. Both OSes will appear in the OpenCanopy picker

**Windows installer warning:** the Windows installer likes to drop its boot
files onto whichever EFI partition it finds first, which may be the NVMe's —
the one macOS is now using. To avoid that, physically disconnect the NVMe or
use the installer's custom partitioning to make sure Windows creates its own
EFI/MSR partitions on the Crucial. If Windows does clobber things, Emergency
Recovery at the end of this guide has the `bcdboot` fix.

**Populating M2_2 disables PCI_E4** on this board — so once Windows is on the
Crucial, the WiFi card must live in PCI_E2 or PCI_E3. See Phase 8.1.

**Sanity checks once Sequoia is running from NVMe:**

```bash
# Should report the XPG, connected via PCI-Express / NVMe
diskutil info / | grep -E "Device Node|Protocol|Media Name"

# TRIM should read Yes
system_profiler SPNVMeDataType | grep -i trim
```

If the NVMe shows up as an **external** (orange) disk in Finder, macOS has
mis-detected it. That is fixed with a `built-in` property on the drive's
`PciRoot` path in `DeviceProperties`, the same way the ethernet controller is
handled — run `tools/collect-diagnostics.sh` to get the actual path first.

### 5.4 Install macOS Sequoia

1. Back in the macOS Utilities window, click **Install macOS Sequoia**
2. Click **Continue**, accept the license agreement
3. Select the drive you just erased (`Macintosh HD`)
4. Click **Install**

The installation process:
- First phase: copies files to the drive (shows a progress bar)
- Then it **reboots automatically** — this is where you need to pay attention

### 5.5 Handle the reboots (critical!)

The Sequoia installation reboots 2-3 times. Each time, you need to
select the right entry in the OpenCanopy picker.

**First reboot:**
- The picker shows several entries
- Select **"macOS Installer"** (NOT "Install macOS Sequoia")
  - "macOS Installer" = the in-progress installation on your hard drive
  - "Install macOS Sequoia" = the USB installer you already used
- This continues the installation. More verbose text, more progress.

**Second reboot:**
- Select **"macOS Installer"** again
- More installation progress

**Third reboot (usually the last):**
- You should now see **"Macintosh HD"** (or whatever you named it)
  instead of "macOS Installer"
- Select it
- This boots into the fresh Sequoia setup wizard

### 5.6 Complete the Sequoia setup wizard

1. Select your country/region
2. Select keyboard layout
3. Connect to network:
   - **Ethernet** (recommended): should auto-connect, just click Continue
   - If you already have the BCM94360CD: select your WiFi network
   - If no network available: click "Other Network Options" or skip — you
     can connect via ethernet after setup completes
4. At the "Migration Assistant" screen:
   - If you want to restore from Time Machine: select **"From a Mac, Time
     Machine backup, or Startup disk"** and follow the prompts
   - If you want a truly fresh start: select **"Not Now"**
5. **Do NOT sign into Apple ID yet** — we need to fix things first
   - Click "Set Up Later" or "Skip" when asked for Apple ID
6. Create your local user account
7. Finish the remaining setup screens

---

## Phase 6: Post-install configuration

### 6.1 Make the EFI permanent (move from USB to hard drive)

Right now you're booting from the USB's EFI. You need to copy it to your
hard drive so you can boot without the USB.

```bash
# Open Terminal (Spotlight > type Terminal)

# Find your drives
diskutil list

# Identify:
# - Your macOS SATA drive (has "Macintosh HD" APFS partition)
# - Its EFI partition (usually the first partition, e.g., disk0s1)
# - Your USB drive (has the working EFI)

# Mount your SATA drive's EFI partition
sudo diskutil mount disk0s1
# "Volume EFI on disk0s1 mounted"

# Mount the USB's EFI partition (if not already mounted)
sudo diskutil mount disk2s1

# Check what's on the hard drive's EFI (may be empty or have old stuff)
ls /Volumes/EFI/EFI/ 2>/dev/null
# If there's old stuff, remove it first:
sudo rm -rf /Volumes/EFI/EFI

# Copy from USB to hard drive
# Note: /Volumes/EFI is the hard drive, /Volumes/EFI\ 1 (or similar) is the USB
# Use: ls /Volumes/ to see the exact names
sudo cp -R "/Volumes/EFI 1/EFI" /Volumes/EFI/

# Verify
ls /Volumes/EFI/EFI/OC/config.plist
# Should show the file
```

### 6.2 Reboot without the USB

1. Eject/unmount the USB: `diskutil unmount disk2s1`
2. Pull out the USB
3. Restart the computer
4. It should boot from the internal drive's EFI now
5. The OpenCanopy picker appears — select Macintosh HD
6. You're booted into Sequoia from the internal drive!

If it doesn't boot (goes straight to BIOS or Windows), you may need to set
the boot order in BIOS:
1. Enter BIOS (press Del)
2. Go to Boot section
3. Set your SATA drive's UEFI entry as first boot priority
4. Save and exit

### 6.3 Reset NVRAM

This clears stale settings from the old Catalina install and old SMBIOS:

1. Restart the computer
2. At the OpenCanopy picker, press **Space** on your keyboard
   - This reveals hidden/auxiliary entries
3. You should see a **"Reset NVRAM"** option
4. Select it and press Enter
5. The system reboots with fresh NVRAM
6. Boot into macOS normally

### 6.4 Sign into Apple ID and fix iServices

1. First, clean out any stale iServices data. Open Terminal:
```bash
sudo rm -rf ~/Library/Caches/com.apple.iCloudHelper*
sudo rm -rf ~/Library/Caches/com.apple.Messages*
sudo rm -rf ~/Library/Caches/com.apple.imfoundation.IMRemoteURLConnectionAgent*
sudo rm -rf ~/Library/Preferences/com.apple.iChat*
sudo rm -rf ~/Library/Preferences/com.apple.icloud*
sudo rm -rf ~/Library/Preferences/com.apple.imagent*
sudo rm -rf ~/Library/Preferences/com.apple.imessage*
sudo rm -rf ~/Library/Preferences/com.apple.imservice*
sudo rm -rf ~/Library/Preferences/com.apple.ids.service*
sudo rm -rf ~/Library/Preferences/com.apple.madrid.plist*
sudo rm -rf ~/Library/Preferences/com.apple.imessage.bag.plist*
sudo rm -rf ~/Library/Preferences/com.apple.identityserviced*
sudo rm -rf ~/Library/Preferences/com.apple.security*
sudo rm -rf ~/Library/Messages
```

2. Reboot

3. **Sign into Apple ID:**
   - Open **System Settings** > **Sign in with your Apple ID** (at the top)
   - Enter your Apple ID and password
   - Complete 2FA if prompted
   - Wait for iCloud to finish syncing (can take a few minutes)

4. **Enable iMessage:**
   - Open the **Messages** app
   - If prompted to sign in: enter your Apple ID credentials
   - If it says "Waiting for activation..." — this is normal, wait up to 24 hours
   - If it works immediately — great!

5. **Enable FaceTime:**
   - Open the **FaceTime** app
   - Sign in if prompted
   - Same activation wait may apply

**If iMessage says "Could not sign in" or gets stuck:**
- Wait 24 hours — Apple's activation servers can be slow for new hardware IDs
- Verify your serial is invalid at checkcoverage.apple.com
- Check that your ethernet adapter shows as `en0`:
  ```bash
  networksetup -listallhardwareports
  # Ethernet should be listed with Device: en0
  ```
- If `en0` is not your Ethernet, reset network config:
  ```bash
  sudo rm /Library/Preferences/SystemConfiguration/NetworkInterfaces.plist
  sudo rm /Library/Preferences/SystemConfiguration/preferences.plist
  ```
  Then reboot.
- As a last resort, call Apple Support — they can reset the activation on
  their end without knowing it's a hackintosh

### 6.5 Test USB ports and remap if needed

Your old `USBPorts.kext` from the Catalina setup is included. Test every
USB port on your computer:

1. Plug a USB device into each port (front panel, back panel)
2. Check System Information > USB to see if each one shows up
3. Test both USB 2.0 devices (like a mouse) and USB 3.0 devices (like a
   thumb drive)

If some ports don't work:
1. Download [USBToolBox](https://github.com/USBToolBox/tool/releases) on Windows
   (easier than doing it from macOS)
2. Boot into Windows
3. Run the USBToolBox tool
4. It auto-discovers all ports. Follow its prompts to generate a new
   `UTBMap.kext` and `USBToolBox.kext`
5. Replace `USBPorts.kext` in `EFI/OC/Kexts/` with the new kexts
6. Update `config.plist` to reference the new kext names

### 6.6 Audio troubleshooting

If audio doesn't work out of the box:

1. Open **System Settings** > **Sound** > **Output**
2. Check if your audio device is listed
3. If no sound, try a different AppleALC layout-id:
   ```bash
   # Your codec is ALC892. alcid=1 is the default.
   # To try a different layout, edit boot-args:

   # Mount EFI
   sudo diskutil mount disk0s1

   # Open config.plist in a text editor or ProperTree
   # Find boot-args line:
   #   -v debug=0x100 keepsyms=1 alcid=1 shikigva=128 -radcodec revpatch=pci,cpuname
   # Change alcid=1 to alcid=31
   # Save
   ```
4. Reset NVRAM (important — the old alcid gets cached)
5. Reboot and test audio
6. If alcid=31 doesn't work, try: 97, 28, 15, 12, 7, 5, 4, 3, 2
7. Reset NVRAM between each change

### 6.7 Remove verbose mode (once everything is stable)

After everything is working, you don't need the scrolling text during boot:

1. Mount EFI partition:
   ```bash
   sudo diskutil mount disk0s1
   ```
2. Open config.plist with ProperTree (or a text editor)
3. Find `NVRAM` > `Add` > `7C436110-AB2A-4BBB-A880-FE41995C9F82` > `boot-args`
4. Current value:
   `-v debug=0x100 keepsyms=1 alcid=1 shikigva=128 -radcodec revpatch=pci,cpuname`
5. Remove the `-v` at the beginning. Leave everything else alone —
   `revpatch=pci,cpuname` is what suppresses the MacPro7,1 "PCI configuration"
   and RAM warnings, and dropping it brings the nag back.
6. Save

Because `boot-args` is listed under `NVRAM` > `Delete`, the new value takes
effect on the next boot without needing an NVRAM reset.

Optionally, also reduce debug logging:
- Set `Misc` > `Debug` > `Target` to `3` (instead of 67)
- Set `Misc` > `Debug` > `AppleDebug` to `NO`
- Set `Misc` > `Debug` > `LogModules` to `*` -> leave as is, or narrow it
- This stops writing a log file to the EFI partition on every boot

7. Reboot. You'll now see the Apple logo during boot instead of text.

---

## Phase 7: Final verification checklist

Go through each item and confirm it works:

**Boot & System:**
- [ ] Sequoia boots cleanly (Apple logo, no text) after removing -v
- [ ] OpenCanopy GUI picker shows with BsxM1 theme
- [ ] Mouse pointer works in the picker
- [ ] Keyboard arrow keys and Enter work in picker
- [ ] Hotkeys work: Cmd+V (verbose), Space (show hidden entries)
- [ ] Windows boots from the picker and you can switch back to macOS
- [ ] System Information > Hardware Overview shows MacPro7,1

**Hardware:**
- [ ] Audio output works (speakers or headphones via 3.5mm jack)
- [ ] Ethernet works (wired internet), and `networksetup -listallhardwareports`
      shows Ethernet as **en0**
- [ ] WiFi works (only after Phase 8 — skip if still on the old card)
- [ ] Bluetooth works (only after swapping to BCM943602CS)
- [ ] All USB ports work (front and back, USB 2 and USB 3)
- [ ] GPU acceleration works (smooth animations, no glitches)
- [ ] Sleep/Wake works (Apple menu > Sleep, then wake with keyboard/mouse)
- [ ] macOS is booting from the **XPG NVMe** — `diskutil info / | grep Protocol`
      reports PCI-Express, and the drive shows as internal (not orange) in Finder
- [ ] TRIM is on — `system_profiler SPNVMeDataType | grep -i trim` says Yes
- [ ] Crucial NVMe is visible in Disk Utility (your Windows partition)
- [ ] Sleep/wake survives several cycles. If it does not, the SM2262EN's APST
      behaviour is the first suspect — try `-nvmefaspm`, or set the
      `ps-max-latency-us` property on the drive's parent PCI device to 0 to
      disable APST entirely (see the NVMeFix README)
- [ ] CPU temps read out (iStat Menus / HWMonitor via SMCAMDProcessor)
- [ ] GPU temps read out (SMCRadeonSensors)

**Cosmetic checks that catch config mistakes:**
- [ ] No "PCI configuration" or memory warning badge in System Settings —
      that is `revpatch=pci` doing its job
- [ ] About This Mac shows a real CPU name, not "Unknown" — `revpatch=cpuname`
- [ ] `sysctl -n kern.hv_vmm_present` returns **0**. A 1 means something is
      still forcing the VMM Secure Boot model and Content Caching will break.

**Apple Services:**
- [ ] iCloud syncs (contacts, calendar, photos, etc.)
- [ ] iMessage sends and receives
- [ ] FaceTime works
- [ ] App Store lets you download apps
- [ ] Apple ID shows in System Settings

---

## Phase 8: Swap to the BCM943602CS and restore WiFi

This phase is completely independent. Do it a day later, a week later,
or a month later. Everything else works on ethernet in the meantime.

### 8.0 What you are actually up against

The BCM943602CS is a genuine Apple card and macOS used to drive it with no
kexts at all. That stopped being true:

| macOS | Broadcom WiFi |
|---|---|
| Ventura 13 and earlier | Native, zero configuration |
| Sonoma 14 | Apple starts pulling the stack apart |
| **Sequoia 15** | **`IO80211FamilyLegacy.kext` is gone — no driver at all** |
| Tahoe 26 | Still gone; OCLP root patches no longer work either |

Nothing about the card is wrong and no other Broadcom card avoids this — a
BCM94360CD or Fenvi T919 lands in exactly the same place. Bluetooth is a
separate USB-attached device and is unaffected.

The workaround, already configured in this EFI:

1. `Kernel` > `Block` excludes Sequoia's `com.apple.iokit.IOSkywalkFamily`
2. `Kernel` > `Add` entries 14–17 inject the Ventura stack in its place:
   `AMFIPass` + `IOSkywalkFamily` + `IO80211FamilyLegacy` (whose
   `AirPortBrcmNIC` plugin is the actual driver)
3. `SecureBootModel` is `Disabled` and `csr-active-config` is `03080000`,
   because Apple Secure Boot and full SIP both reject the downgraded kexts

`AirPortBrcmNIC` matches `pci14e4,43ba`, which is the BCM43602 chip on your
card — so the driver and the hardware do line up.

**The ongoing cost:** you are running without Apple Secure Boot and with SIP
partially disabled, and a macOS update can replace the networking stack and
require re-patching. If that trade is not worth it, section 8.5 shows how to
back it out and keep Bluetooth.

### 8.1 Card form factor and which slot to use

The BCM943602CS module itself is a small Apple form factor — not mini-PCIe, not
M.2 Key-M. It normally arrives already mounted on a **Fenvi-style PCIe x1
carrier board** with the antennas attached, which is what you want; a bare
module would need that adapter bought separately.

**Slot layout on the B450M Mortar Max:**

| Slot | Width | Used by |
|---|---|---|
| PCI_E1 | PCIe 3.0 x16 | RX 460 |
| PCI_E2 | PCIe 2.0 x1 | free |
| PCI_E3 | PCIe 2.0 x1 | **WiFi card goes here** |
| PCI_E4 | PCIe 2.0 x16 (x4 mode) | dead once M2_2 is populated |

Two pairs share lanes — the board wires the same chipset lanes to two places,
so the loser is dead, not just slower:

| If you populate | This becomes unavailable |
|---|---|
| M2_2 (second M.2) | PCI_E4 |
| PCI_E3 | PCI_E2 |

**None of this stops the WiFi card working.** The Fenvi-style carrier is a
PCIe **x1** card, and both x1 slots (PCI_E2, PCI_E3) are completely unaffected
by the M.2 slots. Only PCI_E4 — the big lower x16 slot, which you have no
reason to use — is lost to M2_2.

So: **put the WiFi card in PCI_E3.** PCI_E2 works equally well electrically,
but on mATX it usually sits directly under PCI_E1 and a dual-slot RX 460 will
physically cover it. Using PCI_E3 disables PCI_E2, which costs you nothing
since you only have one card to fit.

Do **not** use PCI_E4 with a drive in M2_2 — the card simply will not appear,
and no amount of config debugging will find it. If WiFi ever vanishes right
after you move a drive around, check this before anything else.

### 8.1b You do not need to change SMBIOS

Worth stating plainly, because the card never shipped in a Mac Pro and it is a
reasonable thing to worry about: **keep MacPro7,1.** macOS does not gate WiFi
cards on SMBIOS model.

- `AirPortBrcmNIC` matches on PCI ID (`IONameMatch` = `pci14e4,43ba`). There is
  no model or board-id in its match dictionary.
- The driver binary does contain a 25-entry board-id table, but that is
  `cpmChanSwitchWhitelist` — a per-board channel-switching tuning list, and it
  only applies to the older `AirPort_Brcm4360` driver variant. AirportBrcmFixup's
  own `checkBoardId` hook returns *allow* for anything not in that list, which
  is the default path. iMacPro1,1 — far and away the most common hackintosh
  SMBIOS for these cards — is absent from it too.
- BCM43602 shipped in desktops anyway; the iMac (Retina 5K, 2015/2017) used the
  BCM943602CDP, the same chip in the full-size form factor.

Changing SMBIOS would also cost you real things: MacPro7,1 is IGPU-free, which
per WhateverGreen's own DRM notes is what allows full DRM content access with an
AMD dGPU and no integrated graphics. An iMac SMBIOS expects an iGPU and would
need a connector-less framebuffer to avoid degrading that. You would also
regenerate serial/MLB/UUID and redo iServices activation from scratch.

### 8.2 Confirm the kexts are on the EFI first

Do this **before** opening the case. If `IOSkywalkFamily` is blocked with
nothing to replace it, you get no WiFi and a confusing debug session.

```bash
sudo diskutil mount disk0s1
ls /Volumes/EFI/EFI/OC/Kexts/ | grep -E "AMFIPass|IOSkywalk|IO80211"
# Expect: AMFIPass.kext  IO80211FamilyLegacy.kext  IOSkywalkFamily.kext

# And the driver plugin specifically:
ls /Volumes/EFI/EFI/OC/Kexts/IO80211FamilyLegacy.kext/Contents/PlugIns/
# Expect: AirPortBrcmNIC.kext
```

Missing? Run `./tools/fetch-wifi-kexts.sh` and re-copy the Kexts folder.

### 8.3 Swap the card

1. Shut down the computer completely
2. Unplug the power cable
3. Open the case
4. Find the BCM94331CD WiFi card (small card, 2 antenna wires)
5. Disconnect the 2 antenna cables — gently pull straight up with
   fingers or small pliers. They snap off.
6. Unscrew the single screw holding the card
7. Pull the card out at an angle
8. Seat the BCM943602CS in its adapter, then fit the adapter to the slot
9. Screw it in
10. Reconnect the 2 antenna cables (press down firmly until they click)
11. Close the case, reconnect power

### 8.4 Boot and test

1. Boot into macOS
2. Reset NVRAM once (Space in the picker > Reset NVRAM) so the new
   `csr-active-config` is definitely applied
3. Click the WiFi icon in the menu bar — you should see available networks
4. Open **System Settings** > **Bluetooth** — it should show "Bluetooth: On"
5. Try pairing a Bluetooth device

Verify the pieces actually loaded:

```bash
# The card should be detected
system_profiler SPAirPortDataType

# The injected driver should be resident
kmutil showloaded --collection auxiliary | grep -iE "80211|Skywalk|BrcmNIC"

# SIP should read as partially disabled — this is expected, not a mistake
csrutil status
```

**If WiFi still doesn't appear:**

- Re-check 8.2 — a missing kext is by far the most common cause
- Confirm the block took effect: the OpenCore log should show
  `IOSkywalkFamily` excluded. Mount the EFI and read `opencore-*.txt`.
- Confirm `csrutil status` is not "enabled". If it is, the NVRAM value did
  not stick — check that `csr-active-config` appears under `NVRAM` > `Delete`
  as well as `NVRAM` > `Add`, then reset NVRAM again.
- Then, and only then, run **OpenCore Legacy Patcher** and apply
  **Post-Install Root Patch → Networking: Modern Wireless**. Reboot.
  This has to be re-applied after macOS updates.

**If WiFi appears but misbehaves** — no 5GHz networks, wrong regulatory
domain, link drops after wake — add
[AirportBrcmFixup](https://github.com/acidanthera/AirportBrcmFixup) 2.2.0 as a
Lilu plugin. It is deliberately **not** in this EFI, because most of what it
patches targets non-Apple cards and the BCM943602CS is genuine Apple silicon —
adding it by default would be risk without benefit. The knobs worth knowing:

| Boot-arg | What it does |
|---|---|
| `brcmfx-country=US` | Sets the regulatory domain (`#a` = follow the AP) |
| `brcmfx-delay=15000` | Delays driver start; fixes "no WiFi device" races |
| `brcmfx-aspm=0` | Disables ASPM if the link drops after sleep |
| `-brcmfxbeta` | Allows loading on a macOS version it does not yet whitelist |

**If Bluetooth doesn't work:**

- Check that BlueToolFixup.kext is enabled in config.plist
- Reset NVRAM and reboot
- Check System Information > Bluetooth — is the controller listed?

**After a macOS update breaks WiFi again:** that is the expected failure mode.
Re-run the OCLP root patch. If an update ever breaks it beyond that, section
8.5 gets you back to a clean, fully-secured machine on Ethernet.

### 8.5 Backing the WiFi patch out

If you decide the Secure Boot / SIP trade is not worth it, revert these four
things in `config.plist` and you are back to a stock-security machine with
working Bluetooth and Ethernet:

| Setting | Patched value | Revert to |
|---|---|---|
| `Kernel` > `Add` entries 14–17 | Enabled | Disabled (or delete) |
| `Kernel` > `Block` IOSkywalkFamily | Enabled | Disabled |
| `Misc` > `Security` > `SecureBootModel` | `Disabled` | `Default` |
| `NVRAM` > `csr-active-config` | `03080000` | `00000000` |

Reset NVRAM afterwards. The other route is an Intel AX210 with
`AirportItlwm` — native menu-bar WiFi with SIP and Secure Boot fully intact,
at the cost of unreliable AirDrop/Handoff/Continuity, and a kext that must be
matched to each macOS version.

### 8.6 Update the checklist

Now go back and tick off the WiFi and Bluetooth items from Phase 7.

---

## Debugging with Claude Code

If something goes wrong, you can use Claude Code to instantly diagnose
OpenCore logs, kernel panics, and config issues. This is much faster than
googling error messages on forums.

### Scenario A: macOS boots but something is broken

You're in macOS and can open Terminal. Run Claude Code directly:

```bash
# Feed your config for analysis
claude "check this opencore config for issues" < /Volumes/EFI/EFI/OC/config.plist

# Or feed the OC boot log
claude "diagnose this opencore boot log, what went wrong?" < /Volumes/EFI/opencore-*.txt

# Or a kernel panic log
claude "explain this kernel panic and how to fix it" < /Library/Logs/DiagnosticReports/*.panic

# Or check system logs for errors
log show --last 5m --predicate 'eventMessage contains "error"' > /tmp/syslog.txt
claude "any hackintosh-related errors in this log?" < /tmp/syslog.txt
```

You can also just start a conversation and paste errors:

```bash
claude
# Then type or paste: "I get this error during boot: [paste error text]"
# Claude has full context of your Ryzentosh setup from this repo
```

### Scenario B: macOS doesn't boot, but Windows does

Boot into Windows (F11 > select NVMe), then:

1. **Install Claude Code on Windows** (if not already):
   ```powershell
   npm install -g @anthropic-ai/claude-code
   ```

2. **Mount the EFI partition** to read OC logs:
   ```powershell
   # Open PowerShell as Administrator
   mountvol S: /s
   # Or use: diskpart > select disk 0 > select partition 1 > assign letter=S

   # The OC log file will be at S:\opencore-*.txt
   ```

3. **Feed the log to Claude Code:**
   ```powershell
   claude "diagnose this opencore boot log for my AMD Ryzen hackintosh" < S:\opencore-2026-04-01-143022.txt
   ```

4. **Feed the config for review:**
   ```powershell
   claude "check this opencore config for AMD Ryzen 2700 hackintosh issues" < S:\EFI\OC\config.plist
   ```

### Scenario C: Nothing boots, you're on your phone

1. Take a **photo of the screen** where it's stuck (the verbose text or
   error message)
2. Open Claude on your phone (claude.ai)
3. Upload the photo and ask: "My AMD hackintosh is stuck at this point
   during boot. I'm running OpenCore 1.0.7 with Ryzen 2700, RX 460,
   MSI B450M Mortar Max targeting macOS Sequoia. What's wrong?"

### Scenario D: Boot fails, you have a second Mac/Linux machine

1. Pull the USB EFI stick and plug it into the working machine
2. Mount it and read the log:
   ```bash
   # macOS:
   sudo diskutil mount disk2s1
   cat /Volumes/EFI/opencore-*.txt

   # Linux:
   sudo mount /dev/sdb1 /mnt
   cat /mnt/opencore-*.txt
   ```
3. Feed to Claude Code on that machine:
   ```bash
   claude "diagnose this opencore boot failure" < /Volumes/EFI/opencore-*.txt
   ```

### Quick one-liners for common checks

```bash
# "Why won't my hackintosh boot?"
sudo diskutil mount disk0s1 && claude "diagnose boot failure" < /Volumes/EFI/opencore-*.txt

# "Is my config correct?"
sudo diskutil mount disk0s1 && claude "audit this OC 1.0.7 config for AMD Ryzen 2700 + RX 460" < /Volumes/EFI/EFI/OC/config.plist

# "What kexts am I loading?"
sudo diskutil mount disk0s1 && claude "list all enabled kexts and check loading order" < /Volumes/EFI/EFI/OC/config.plist

# "Why is my audio not working?"
system_profiler SPAudioDataType > /tmp/audio.txt && claude "audio not working on hackintosh with ALC892, here is my audio info" < /tmp/audio.txt

# "Why did it kernel panic?"
claude "explain this hackintosh kernel panic" < /Library/Logs/DiagnosticReports/*.panic

# "Compare my config against Dortania recommendations"
sudo diskutil mount disk0s1 && claude "compare this config against Dortania AMD Zen guide recommendations, flag anything wrong" < /Volumes/EFI/EFI/OC/config.plist
```

### Tips for getting the best help from Claude

- **Always mention your hardware**: "Ryzen 2700, RX 460, MSI B450M Mortar Max"
- **Include the OC version**: "OpenCore 1.0.7"
- **Include the macOS target**: "macOS Sequoia 15"
- **Feed actual files** rather than describing the problem — Claude can parse
  plist XML, boot logs, and panic reports directly
- **If Claude is running in this repo directory**, it already has context from
  config.plist, the upgrade guide, and all the decisions made during setup

---

## Emergency Recovery

### "I broke everything and can't boot macOS at all"

1. Your **old EFI backup** (from step 1.1) is on your external drive
2. Format a USB as GUID, mount its EFI partition
3. Copy the old EFI backup to the USB
4. Boot from the USB — it will load your old Catalina with the old OC 0.6.3
5. You're back to square one, nothing lost

### "The new EFI doesn't boot but my old Catalina still works"

1. Remove the USB, boot normally — your hard drive still has the old EFI
2. Mount the USB's EFI in Catalina
3. Check the OC log file on the USB for errors
4. Fix the config.plist issue
5. Try again

### "Sequoia installed but won't boot"

1. Boot from the installer USB #2 (it has the same EFI)
2. In the picker, select your installed Sequoia drive
3. If it boots, the issue is your hard drive's EFI — recopy from USB
4. If it doesn't boot, check verbose output for the specific error

### "Windows won't boot from the picker anymore"

1. Verify `ScanPolicy` is `0` in config.plist
2. Verify `RequestBootVarRouting` is `YES`
3. Boot into BIOS (F11) and boot Windows directly from the BIOS boot menu
4. Once in Windows, open an admin Command Prompt and run:
   ```
   bcdboot C:\Windows /s S: /f UEFI
   ```
   This rebuilds the Windows boot entry

### "iServices completely broken — Can't sign in at all"

1. Generate completely new SMBIOS values (new serial, MLB, UUID)
2. Reset NVRAM
3. Run the cache cleanup commands from step 6.4
4. Try signing in with a **different/test Apple ID** first to rule out
   account-level blocking
5. If you get a "Customer Code" error, you must call Apple Support
   (they can unblock it without knowing it's a hackintosh)
