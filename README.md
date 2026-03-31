## OpenCore EFI for AMD Ryzen Hackintosh


[![macOS version](https://img.shields.io/badge/macOS-Sequoia_15-informational.svg)](https://www.apple.com/macos)
[![OpenCore version](https://img.shields.io/badge/OpenCore-1.0.6-informational.svg)](https://github.com/acidanthera/OpenCorePkg)



## Specification


| **Component** | **Model** |
| ------------- | --------- |
| CPU | AMD Ryzen 7 2700 @ 3.2GHz (8-core) |
| Motherboard | MSI B450M Mortar Max |
| RAM | 16GB (2 x 8GB) Crucial Ballistix @ 3200MHz |
| Audio Chipset | Realtek ALC892 |
| GPU | RX 460 (Polaris) |
| WiFi & Bluetooth | BCM94360CD (native Apple chipset) |
| Ethernet | Realtek RTL8111 |
| macOS Disk | SATA SSD |
| Windows Disk | Kingston A400 256GB NVMe |

**macOS version**: Sequoia 15

**OpenCore version**: 1.0.6

**SMBIOS**: MacPro7,1

## What is working

- Audio (ALC892 via AppleALC, layout-id 1)
- Ethernet (Realtek RTL8111)
- WiFi (BCM94360CD - native, no kext needed)
- Bluetooth (BCM94360CD via BlueToolFixup on macOS 12+)
- GPU acceleration (RX 460 Polaris - native drivers)
- Sleep/Wake
- USB (custom mapped via USBPorts.kext)
- iMessage, FaceTime, iCloud
- Windows dual-boot (NVMe)
- OpenCanopy GUI picker with BsxM1 theme
- NVMe power management (NVMeFix)

## What is not working

- Partially-working virtualization (only VirtualBox & Parallels Desktop 13.1.0 or below) - this is an AMD limitation
- 3.5mm jack microphone (only USB/Bluetooth microphones work) - can be fixed with VoodooHDA but sacrifices audio quality
- Adobe apps require [patches](https://github.com/ArtSabintsev/Adobe-CC-Fonts-Support) for AMD

## Kexts

| Kext | Version | Purpose |
|------|---------|---------|
| [Lilu](https://github.com/acidanthera/Lilu) | 1.7.2 | Core patching engine |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) | 1.3.7 | SMC emulation |
| [WhateverGreen](https://github.com/acidanthera/WhateverGreen) | 1.7.0 | GPU patching |
| [AppleALC](https://github.com/acidanthera/AppleALC) | 1.9.7 | Audio patching |
| [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X) | 3.0.0 | Ethernet |
| [BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM) | 2.7.2 | Bluetooth fix for macOS 12+ |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) | 1.1.6 | macOS event patching |
| [AMDRyzenCPUPowerManagement](https://github.com/trulyspinach/SMCAMDProcessor) | 0.7.2 | Ryzen power management |
| [SMCAMDProcessor](https://github.com/trulyspinach/SMCAMDProcessor) | 1.0.1 | CPU sensor data |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) | 1.1.3 | NVMe power management |
| [AppleMCEReporterDisabler](https://github.com/AMD-OSX/AMD_Vanilla) | 1.0 | Prevents MCE panics on AMD |
| USBPorts | 1.0 | Custom USB port map |

## ACPI

| SSDT | Purpose |
|------|---------|
| SSDT-EC-USBX | Embedded Controller + USB power fix for AMD 17h |

## Drivers

| Driver | Purpose |
|--------|---------|
| OpenRuntime.efi | OpenCore boot.efi patching |
| HfsPlus.efi | HFS+ filesystem support |
| OpenCanopy.efi | GUI boot picker |
| ResetNvramEntry.efi | NVRAM reset from picker |

## How to use

1. Make your USB installer with [**this guide**](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/)
2. Clone the repository and paste the `EFI` folder into your USB's EFI partition
3. Download [**GenSMBIOS**](https://github.com/corpnewt/GenSMBIOS) to generate unique SMBIOS information. Run it and select **Generate SMBIOS**, as the model select **MacPro7,1**
4. Open config.plist with [**ProperTree**](https://github.com/corpnewt/ProperTree) and go to PlatformInfo > Generic. Set MLB (Board Serial), SystemSerialNumber (Serial) and SystemUUID (SmUUID) to generated values. Change ROM to your network card's MAC address without the `:` character. [**How to get MAC Address?**](https://www.wikihow.com/Find-the-MAC-Address-of-Your-Computer)
5. Verify the generated serial is **invalid** at [Apple's coverage checker](https://checkcoverage.apple.com/) - it should say "Unable to check coverage"
6. If you have a different CPU core count, update the 4 "Force cpuid_cores_per_package" kernel patches - change the core count byte in Replace values (04=4-core, 06=6-core, 08=8-core, 0C=12-core, 10=16-core)
7. Boot it!

See [**UPGRADE-GUIDE.md**](UPGRADE-GUIDE.md) for a detailed step-by-step upgrade guide including debugging tips.

**IMPORTANT:**
- You MUST generate your own SMBIOS values with GenSMBIOS for iMessage/FaceTime to work
- If you have a different motherboard, you need to re-map USB ports with [USBToolBox](https://github.com/USBToolBox/tool)
- The WiFi card (BCM94360CD) is a native Apple chipset - no kexts needed for WiFi. BlueToolFixup is only for Bluetooth on macOS 12+
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
 - [[Kext] AppleMCEReporterDisabler](https://github.com/AMD-OSX/AMD_Vanilla/blob/experimental-opencore/Extra/AppleMCEReporterDisabler.kext.zip)


**Guides/Support**

 - [Apple](https://apple.com) for macOS
 - [AMD-OSX Developers](https://github.com/AMD-OSX) for kernel patches for AMD CPUs
 - [Acidanthera](https://github.com/acidanthera) for OpenCore and most of used kexts
 - [Trulyspinach](https://github.com/trulyspinach) for Ryzen power management and monitoring kexts
 - [Mieze](https://github.com/Mieze) for RealtekRTL8111 kext
 - [Blackosx](https://github.com/blackosx) for BsxM1 OpenCanopy theme
 - [Dortania](https://github.com/dortania) for OpenCore configuration guides
 - [AMD-OSX Community](https://amd-osx.com) for support while making my Hackintosh


If you have any questions, please open an issue :)

Cheers!
