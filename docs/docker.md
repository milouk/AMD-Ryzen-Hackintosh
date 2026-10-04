# Docker on this machine

macOS only offers hardware virtualization through Apple's Hypervisor
framework, which does not work on AMD CPUs. Docker Desktop, OrbStack, Colima
and current VirtualBox are therefore out.

What is used instead is **Graft**: the BSD hypervisor NVMM ported to macOS as
a kernel extension, with a small virtual machine monitor and a start/stop
script on top. It lives in its own repository, not published yet; its README
is the reference for building, loading and known issues.

State on 2026-10-05, on the Catalina install:

- The driver loads at run time (`kextutil`) and runs Linux guests.
- `nvmm-docker start` boots an Alpine VM in about six seconds, and a `docker`
  client on macOS runs containers in it through a socket.
- It needs SIP's kext-signing check off. Catalina was changed from
  `csr-active-config 00000000` to `67000000` for this; the Sequoia EFI in
  this repository already has `03080000`, which is enough.
- Networking goes through gvproxy: macOS's vmnet did not answer on Catalina.

After the Sequoia migration ([UPGRADE-GUIDE.md](../UPGRADE-GUIDE.md)):

1. Build and load the kext on Sequoia. The engine has not run there yet.
2. Use current QEMU and gvproxy builds, which Catalina was too old for.
3. Install with a package manager that still supports Intel: MacPorts.
   Homebrew's installer refuses x86_64 Macs.

Fallbacks if it does not work on Sequoia: VirtualBox 6.1.50 run headless (the
last release with its own AMD-V engine), or a Docker context pointing at
another Linux machine over SSH.
