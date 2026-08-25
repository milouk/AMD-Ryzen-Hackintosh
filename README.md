## OpenCore EFI for AMD Ryzen Hackintosh


[![macOS version](https://img.shields.io/badge/macOS-Sequoia_15-informational.svg)](https://www.apple.com/macos)
[![OpenCore version](https://img.shields.io/badge/OpenCore-1.0.7-informational.svg)](https://github.com/acidanthera/OpenCorePkg)



## Specification


| **Component** | **Model** |
| ------------- | --------- |
| CPU | AMD Ryzen 7 2700 @ 3.2GHz (8-core) |
| Motherboard | MSI B450M Mortar Max |
| RAM | 16GB (2 x 8GB) Crucial Ballistix @ 3200MHz |
| Audio Chipset | Realtek ALC892 |
| GPU | RX 460 (Polaris) |
| WiFi & Bluetooth | BCM943602CS (BCM43602 — `pci14e4,43ba`) |
| Ethernet | Realtek RTL8111 (onboard 8111H) |
| macOS Disk | XPG SX8200 Pro 256GB NVMe (M2_1, PCIe 3.0 x4) — SM2262EN, TLC, DRAM cache |
| Windows Disk | Crucial P310 500GB NVMe (M2_2, PCIe 2.0 x4) — Phison E27T, QLC, DRAM-less |
| Spare | Kingston A400 256GB SATA SSD |
| WiFi slot | PCI_E3 (PCIe 2.0 x1) — **not** PCI_E4, which M2_2 disables |

**macOS version**: Sequoia 15

**OpenCore version**: 1.0.7

**SMBIOS**: MacPro7,1

## What is working

- Audio (ALC892 via AppleALC, layout-id 1)
- Ethernet (Realtek RTL8111)
- Bluetooth (BCM943602CS via BlueToolFixup — works natively on macOS 12+)
- WiFi (BCM943602CS — **requires the restoration kexts, see below**)
- GPU acceleration (RX 460 Polaris — native drivers)
- Sleep/Wake
- USB (custom mapped via USBPorts.kext)
- iMessage, FaceTime, iCloud
- Windows dual-boot (Kingston SATA)
- OpenCanopy GUI picker with BsxM1 theme
- NVMe power management (NVMeFix)
- CPU and GPU temperature sensors (SMCAMDProcessor, SMCRadeonSensors)

## What is not working

- **WiFi is not native on Sequoia.** Apple deleted `IO80211FamilyLegacy.kext` in
  macOS Sequoia, which killed driver support for every Broadcom card — BCM94360,
  BCM943602, Fenvi T919, all of them. This EFI restores it by injecting the
  Ventura-era networking stack, at the cost of Secure Boot and full SIP. See
  [WiFi on Sequoia](#wifi-on-sequoia) below. Bluetooth is unaffected.
- Partially-working virtualization (only VirtualBox & Parallels Desktop 13.1.0 or below) - this is an AMD limitation
- 3.5mm jack microphone (only USB/Bluetooth microphones work) - can be fixed with VoodooHDA but sacrifices audio quality
- Adobe apps require [patches](https://github.com/ArtSabintsev/Adobe-CC-Fonts-Support) for AMD

## WiFi on Sequoia

Broadcom WiFi worked natively through macOS Ventura. Sonoma broke it and Sequoia
finished the job — `IO80211FamilyLegacy.kext` is simply gone from the OS. Buying
a "native Apple" card does not get around this; the card is fine, the driver is
missing.

The fix is to block Sequoia's `IOSkywalkFamily` and inject the Ventura networking
stack in its place. Three bundles do that, two of which are Apple binaries and so
are **not committed to this repository**:

```bash
./tools/fetch-wifi-kexts.sh
```

That pulls them from the [OpenCore Legacy Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher)
payloads into `EFI/OC/Kexts/`. Verified: `AirPortBrcmNIC` matches `pci14e4,43ba`,
which is the BCM43602 chip on the BCM943602CS.

**What this costs you**, and it is already set in `config.plist`:

| Setting | Value | Why |
|---|---|---|
| `Misc > Security > SecureBootModel` | `Disabled` | Apple Secure Boot rejects the downgraded kexts |
| `NVRAM > csr-active-config` | `03080000` | Partial SIP — untrusted kexts, unrestricted FS |
| `Kernel > Block` | `com.apple.iokit.IOSkywalkFamily` excluded | So the injected Ventura build loads instead |

You may also need to run OCLP's root patch (**Post-Install Root Patch → Networking:
Modern Wireless**) if WiFi still does not appear after injection, and it has to be
re-applied after every macOS update. This is the ongoing maintenance cost of
Broadcom WiFi on Sequoia.

> If you would rather keep Secure Boot and full SIP: delete kext entries 14–17,
> disable the `IOSkywalkFamily` block, set `SecureBootModel` back to `Default` and
> `csr-active-config` back to `00000000`. You keep Bluetooth and lose WiFi, and the
> machine runs on Ethernet. An Intel AX210 with AirportItlwm is the other route —
> native menu-bar WiFi with SIP intact, but unreliable AirDrop/Handoff/Continuity.

## Kexts

| Kext | Version | Purpose |
|------|---------|---------|
| [Lilu](https://github.com/acidanthera/Lilu) | 1.7.2 | Core patching engine |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) | 1.3.7 | SMC emulation |
| [WhateverGreen](https://github.com/acidanthera/WhateverGreen) | 1.7.0 | GPU patching |
| [AppleALC](https://github.com/acidanthera/AppleALC) | 1.9.7 | Audio patching |
| [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X) | 3.0.0 | Ethernet |
| [AppleMCEReporterDisabler](https://github.com/AMD-OSX/AMD_Vanilla) | 1.0 | Prevents MCE panics on AMD |
| [AMDRyzenCPUPowerManagement](https://github.com/trulyspinach/SMCAMDProcessor) | 0.7.2 | Ryzen power management |
| [SMCAMDProcessor](https://github.com/trulyspinach/SMCAMDProcessor) | 1.0.1 | CPU sensor data |
| USBPorts | 1.0 | Custom USB port map |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) | 1.1.3 | NVMe power management |
| [BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM) | 2.7.2 | Bluetooth fix for macOS 12+ |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) | 1.1.6 | Suppresses MacPro7,1 PCI/RAM warnings, sets CPU name |
| [SMCRadeonSensors](https://github.com/ChefKissInc/SMCRadeonSensors) | 2.4.0 | AMD GPU temperature monitoring |
| [AMFIPass](https://github.com/dortania/OpenCore-Legacy-Patcher) † | 1.4.1 | AMFI bypass for the injected WiFi kexts |
| IOSkywalkFamily † | 1.2.0 | Ventura build, replaces the blocked Sequoia one |
| IO80211FamilyLegacy † | 1.0.0 | The 802.11 family Apple deleted in Sequoia |
| AirPortBrcmNIC † | 14.0 | Broadcom driver (plugin of IO80211FamilyLegacy) |

† Not in this repository — fetch with `./tools/fetch-wifi-kexts.sh`

The kext load order in `config.plist` is deliberate: Lilu first, VirtualSMC before
its plugins, and `AMDRyzenCPUPowerManagement` before `SMCAMDProcessor` (the latter
reads sensor data collected by the former).

## ACPI

| SSDT | Purpose |
|------|---------|
| SSDT-EC-USBX | Embedded Controller + USB power fix for AMD 17h |

`SSDT-PLUG` is Intel-only and `SSDT-CPUR` is B550/A520-only, so neither applies here.

## Drivers

| Driver | Purpose |
|--------|---------|
| OpenRuntime.efi | OpenCore boot.efi patching |
| HfsPlus.efi | HFS+ filesystem support |
| OpenCanopy.efi | GUI boot picker |
| ResetNvramEntry.efi | NVRAM reset from picker |

## Tools

| Script | Purpose |
|--------|---------|
| `tools/fetch-wifi-kexts.sh` | Downloads the three Broadcom WiFi restoration kexts |
| `tools/verify-efi.sh` | Cross-checks config.plist against what is on disk — catches missing kexts, an inconsistent WiFi patch, bad kext order |
| `tools/apply-smbios.sh` | Generates Serial/MLB/UUID, reads the real ethernet MAC for ROM, patches config.plist — replaces GenSMBIOS + ProperTree |
| `tools/fetch-recovery.sh` | Downloads a macOS Sequoia recovery image (~700MB) — no 15GB installer, no USB stick |
| `tools/install-efi.sh` | Backs up an EFI partition then installs this EFI onto it, verifying before and after |
| `tools/collect-diagnostics.sh` | Read-only snapshot of the running machine — PCI paths, en0, disks, kexts, SIP state |

`ocvalidate` checks the config against OpenCore's schema; `verify-efi.sh` checks
it against reality. Run both before copying `EFI/` anywhere.

Typical run, start to finish:

```bash
./tools/fetch-wifi-kexts.sh                        # once, after cloning
./tools/verify-efi.sh                              # sanity check
./tools/install-efi.sh --list                      # find your target ESP
./tools/install-efi.sh disk2s1                     # backs up, installs, verifies
./tools/apply-smbios.sh /Volumes/EFI/EFI/OC/config.plist
./tools/fetch-recovery.sh /Volumes/SomeVolume      # installer, no USB needed
```

`apply-smbios.sh` edits the plist textually rather than round-tripping it, so
the config keeps all of its explanatory comments. It refuses to write into the
repo copy — those values are your machine's identity and this repo is public.

## Two repos, and the workflow that connects them

This repo is a **public mirror**. The working repo is private, because it carries
the real SMBIOS and tracks Apple's Wi-Fi kexts. Nothing private is meant to reach
this one.

| Repo | SMBIOS | Wi-Fi kexts |
|------|--------|-------------|
| `My-Ryzentosh` (private) | real | tracked |
| `AMD-Ryzen-Hackintosh` (public) | placeholders | fetched by script |

Two GitHub Actions workflows handle it:

| Workflow | Runs | Does |
|----------|------|------|
| `validate.yml` | both repos, on push/PR | ocvalidate, `verify-efi.sh`, confirms the shipped binaries match the official OpenCore release, and proves `fetch-wifi-kexts.sh` still resolves upstream |
| `publish-mirror.yml` | private repo only | sanitizes a copy and pushes it here |

`publish-mirror.yml` is gated on `github.repository`, so it is inert in this repo
and the mirror can never try to publish to itself.

**Auth is a deploy key, not a PAT.** A deploy key is bound to a single
repository, so if the secret ever leaked it could write to this mirror and
nothing else — no other repo, no gists, no account access. A PAT with
`Contents: write` is broader than this job needs. Already installed; recreate
with:

```bash
ssh-keygen -t ed25519 -N '' -f k -C 'mirror-publish@My-Ryzentosh-Actions'
gh repo deploy-key add k.pub --repo milouk/AMD-Ryzen-Hackintosh \
  --title 'mirror-publish (My-Ryzentosh Actions)' --allow-write
gh secret set MIRROR_DEPLOY_KEY --repo milouk/My-Ryzentosh < k
rm k k.pub    # the private half should exist only in the GitHub secret
```

Confirm the key is scoped correctly — GitHub names the repo back at you:

```bash
ssh -F /dev/null -i k -o IdentitiesOnly=yes -o IdentityAgent=none -T git@github.com
# Hi milouk/AMD-Ryzen-Hackintosh! ...   <- repo-scoped, correct
# Hi milouk! ...                        <- your personal key answered instead
```

**Why it is safe to automate.** Publishing is the one step where a mistake is
irreversible, so it is checked three times:

1. `tools/sanitize-for-public.sh` records the real SMBIOS *before* replacing it,
   then greps the entire output tree for those values and exits non-zero if any
   survive anywhere — config, docs, stray notes.
2. An independent audit step in the workflow re-checks the placeholders and the
   absence of the Apple kexts, so a bug in the sanitizer cannot publish on its own.
3. A final step confirms public-only assets (`README.md`, `screenshot.png`)
   survived the mirror copy.

Any of the three failing aborts the job before anything is pushed. The same
sanitizer runs locally: `./tools/sanitize-for-public.sh <tree>`.

For a manual sync between local checkouts, `tools/sync-repos.sh` does the same
job in either direction.

## How to use

1. Make your USB installer with [**this guide**](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/)
2. Clone the repository and run `./tools/fetch-wifi-kexts.sh` — without it the
   `IOSkywalkFamily` block has nothing to fall back to and you get no WiFi
3. Paste the `EFI` folder into your USB's EFI partition
4. Download [**GenSMBIOS**](https://github.com/corpnewt/GenSMBIOS) to generate unique SMBIOS information. Run it and select **Generate SMBIOS**, as the model select **MacPro7,1**
5. Open config.plist with [**ProperTree**](https://github.com/corpnewt/ProperTree) and go to PlatformInfo > Generic. Set MLB (Board Serial), SystemSerialNumber (Serial) and SystemUUID (SmUUID) to generated values. Change ROM to your **ethernet** card's MAC address without the `:` character. [**How to get MAC Address?**](https://www.wikihow.com/Find-the-MAC-Address-of-Your-Computer)
6. Verify the generated serial is **invalid** at [Apple's coverage checker](https://checkcoverage.apple.com/) - it should say "Unable to check coverage"
7. If you have a different CPU core count, update the 4 "Force cpuid_cores_per_package" kernel patches - change the core count byte in Replace values (04=4-core, 06=6-core, 08=8-core, 0C=12-core, 10=16-core)
8. Validate with `ocvalidate` from the OpenCore 1.0.7 release package
9. Boot it!

See [**UPGRADE-GUIDE.md**](UPGRADE-GUIDE.md) for a detailed step-by-step upgrade guide including debugging tips.

**IMPORTANT:**
- You MUST generate your own SMBIOS values with GenSMBIOS for iMessage/FaceTime to work
- `ROM` should be your **Ethernet** MAC, not the WiFi card's — en0 must be Ethernet for iServices
- After any hardware swap, delete `/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist` and reboot so interfaces re-enumerate with Ethernet as en0
- If you have a different motherboard, you need to re-map USB ports with [USBToolBox](https://github.com/USBToolBox/tool)
- BIOS settings: Disable Fast Boot, Secure Boot, CSM, IOMMU. Enable Above 4G Decoding, EHCI/XHCI Hand-off, SATA AHCI mode

## Credits

**Kexts/Resources**

 - [[Bootloader] OpenCore](https://github.com/acidanthera/OpenCorePkg)
 - [[Resources] Picker GUI](https://github.com/acidanthera/OcBinaryData/tree/master/Resources)
 - [[Theme] BsxM1](https://github.com/blackosx/BsxM1)
 - [[Patch] AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla)
 - [[SSDT] EC-USBX-DESKTOP](https://github.com/dortania/Getting-Started-With-ACPI/blob/master/extra-files/compiled/SSDT-EC-USBX-DESKTOP.aml)
 - [[Driver] OpenRuntime](https://github.com/acidanthera/OpenCorePkg)
 - [[Driver] OpenCanopy](https://github.com/acidanthera/OpenCorePkg)
 - [[Driver] HFSPlus](https://github.com/acidanthera/OcBinaryData/blob/master/Drivers/HfsPlus.efi)
 - [[Kext] Lilu](https://github.com/acidanthera/Lilu)
 - [[Kext] VirtualSMC](https://github.com/acidanthera/VirtualSMC)
 - [[Kext] WhateverGreen](https://github.com/acidanthera/WhateverGreen)
 - [[Kext] AppleALC](https://github.com/acidanthera/AppleALC)
 - [[Kext] RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X)
 - [[Kext] BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM)
 - [[Kext] RestrictEvents](https://github.com/acidanthera/RestrictEvents)
 - [[Kext] NVMeFix](https://github.com/acidanthera/NVMeFix)
 - [[Kext] AMDRyzenCPUPowerManagement](https://github.com/trulyspinach/SMCAMDProcessor)
 - [[Kext] SMCAMDProcessor](https://github.com/trulyspinach/SMCAMDProcessor)
 - [[Kext] SMCRadeonSensors](https://github.com/ChefKissInc/SMCRadeonSensors)
 - [[Kext] AppleMCEReporterDisabler](https://github.com/AMD-OSX/AMD_Vanilla/blob/experimental-opencore/Extra/AppleMCEReporterDisabler.kext.zip)
 - [[Kexts] WiFi restoration payloads](https://github.com/dortania/OpenCore-Legacy-Patcher/tree/main/payloads/Kexts)


**Guides/Support**

 - [Apple](https://apple.com) for macOS
 - [AMD-OSX Developers](https://github.com/AMD-OSX) for kernel patches for AMD CPUs
 - [Acidanthera](https://github.com/acidanthera) for OpenCore and most of used kexts
 - [Trulyspinach](https://github.com/trulyspinach) for Ryzen power management and monitoring kexts
 - [Mieze](https://github.com/Mieze) for RealtekRTL8111 kext
 - [Blackosx](https://github.com/blackosx) for BsxM1 OpenCanopy theme
 - [Dortania](https://github.com/dortania) for OpenCore configuration guides and OCLP
 - [perez987](https://github.com/perez987/Broadcom-wifi-back-on-macOS-Sonoma-with-OCLP) and [chriswayg](https://chriswayg.gitbook.io/opencore-visual-beginners-guide) for the Broadcom WiFi restoration method
 - [AMD-OSX Community](https://amd-osx.com) for support while making my Hackintosh


If you have any questions, please open an issue :)

Cheers!
