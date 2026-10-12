# Docker on this machine

macOS only offers hardware virtualization through Apple's Hypervisor
framework, which does not work on AMD CPUs. Docker Desktop, OrbStack, Colima
and current VirtualBox are therefore out.

What is used instead is **[Graft](https://github.com/milouk/graft)**: the BSD
hypervisor NVMM ported to macOS as a kernel extension, with a small virtual
machine monitor (`graft-run`) and a start/stop script (`graft`) on top. Its
README is the reference for building, loading and known issues.

## What it needs

| Piece | Where it comes from |
|---|---|
| `NVMM.kext` and `graft-run` | `make kext vmm` in the Graft repository |
| The VM image (`~/.graft`) | `vmm/build-image.exp`, or built elsewhere and copied |
| `gvproxy` | [gvisor-tap-vsock releases](https://github.com/containers/gvisor-tap-vsock/releases); the VM's network |
| A `docker` client, for the docker flavour | Docker's static macOS binaries |
| SIP allowing unsigned kexts | `csr-active-config` with the kext-signing bit; the Sequoia EFI's `03080000` has it |

Nothing is loaded at boot. After each restart:

```bash
sudo kextutil ~/graft/build/NVMM.kext     # kmutil load -p on macOS 11 and later
sudo chmod 666 /dev/nvmm
~/graft/vmm/graft start
export DOCKER_HOST=unix://$HOME/.graft/docker.sock
```

## State

On the Catalina install, 2026-10-05: the driver loads, Linux boots in about
six seconds on up to eight CPUs, and a `docker` client on macOS runs
containers through the socket, with published ports reachable.

Changes since then have not run on this machine: file sharing (the home
directory mounted in the VM at the same path), memory pinned on demand, and
the read-only root with a separate data disk. `vmm/test.sh` checks all of it.

**On Sequoia 15.8.1, 2026-10-12: it works.** The kext loads at run time with
no approval dialog and no restart, the guest test passes through stage 5, and
`vmm/test.sh` passes in full: containers through the `docker` client, piped
input, a published port answering on the Mac, and a bind mount of a Mac
directory through the file server with a 64 MB checksum round trip. That was
also the first run on real hardware of file sharing, on-demand memory and the
read-only root.

Set up on this machine:

- `~/graft`: the repository and its build, copied from the Catalina install.
- `~/.graft`: the docker-flavour image, and in `~/.graft/bin` a `docker`
  client (Docker's static x86_64 build) and `gvproxy` v0.7.5.
- `~/.zshrc` puts those on the PATH, sets `DOCKER_HOST`, and sizes the VM at
  4 CPUs and 3072 MB. **3072 MB is the most `graft-run` accepts**; asking for
  more makes it print its usage and exit.

After each restart, until this is automated:

```bash
sudo cp -R ~/graft/build/NVMM.kext /private/tmp/ && sudo chown -R root:wheel /private/tmp/NVMM.kext
sudo kmutil load -p /private/tmp/NVMM.kext
sudo chmod 666 /dev/nvmm
graft start
```

## Before it ran on Sequoia, the plan was

1. Clone Graft, `make kext vmm`, load the kext. If the load is refused,
   Sequoia wants the kext approved in System Settings and a restart, or it can
   be injected by OpenCore (`Kernel > Add`); neither has been tried.
2. Copy `~/.graft` from the Kingston, or rebuild the image. The data disk in
   it holds the images and containers.
3. Run `vmm/test.sh`.
4. Install anything else with a package manager that still supports Intel:
   MacPorts. Homebrew's installer refuses x86_64 Macs.

Fallbacks if it does not work on Sequoia: VirtualBox 6.1.50 run headless (the
last release with its own AMD-V engine), or a Docker context pointing at
another Linux machine over SSH.
