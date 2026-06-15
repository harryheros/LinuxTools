# OsNova

> Deterministic OS Reinstallation Engine for VPS and bare-metal servers.

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-2.2.0-brightgreen.svg)](#)
[![Platform](https://img.shields.io/badge/platform-VPS%20%7C%20Bare--metal-black.svg)](#)
[![Arch](https://img.shields.io/badge/arch-x86__64-lightgrey.svg)](#)
[![OS Support](https://img.shields.io/badge/support-Debian%2011%2F12%2F13%20%7C%20Ubuntu%2022.04%2F24.04-green.svg)](#)
[![Language](https://img.shields.io/badge/language-Bash-informational.svg)](#)

---

## Overview

OsNova is an automated Linux deployment and reinstallation tool for VPS and bare-metal systems.

It provides a deterministic way to reinstall Debian or Ubuntu directly from the running system using official upstream resources, without requiring a rescue ISO or external recovery environment.

OsNova prioritizes deterministic behavior, transparency, and minimal assumptions about the host environment.

This project is intended for operators who need a fast, reproducible, infrastructure-oriented reinstall workflow.

Use only on systems you own or are explicitly authorized to manage.

---

## Quick Start

Requires Bash, root privileges, and an x86_64 system.

Review before execution:

```bash
curl -fsSL -o reinstall.sh https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh
less reinstall.sh
```

Default installation (Debian 12):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh)
```

Debian 13 with custom password and SSH port:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -d 13 -p "YourPassword" --port 2222
```

Ubuntu 24.04:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -u 24
```

Ubuntu 22.04:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -u 22
```

Custom DNS example:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -u 24 --dns "1.1.1.1 9.9.9.9"
```

Skip confirmation prompt (for automation):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -u 24 -p "SecurePassword" --port 2222 --force
```

Full example:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/harryheros/osnova/main/os/reinstall.sh) -u 24 -p "SecurePassword" --port 2222 --dns "8.8.8.8 8.8.4.4" --force
```

---

## Data Loss Warning

> ⚠️ This tool will completely erase the primary disk and reinstall the operating system.
>
> All existing data on the target disk will be permanently destroyed.
>
> Do not run it unless you fully understand the consequences.
>
> Starting from v2.0.0, OsNova requires explicit confirmation before proceeding. Use `--force` to skip this prompt in automated workflows.

---

## Features

- Unified Debian and Ubuntu reinstall workflow  
- Works on both BIOS and UEFI systems  
- Cross-distribution execution support  
- Uses official upstream installer or image resources  
- Debian installation via official netboot installer and preseed automation  
- Ubuntu deployment via official cloud image and direct disk write  
- Automatic disk and network detection  
- Static IPv4 migration from the current system  
- Optional IPv6 carry-over when detected  
- IPv4 /32 and IPv6 /128 on-link route handling  
- Debian networking configured with systemd-networkd  
- Ubuntu networking configured with netplan rendered by systemd-networkd  
- Custom DNS server support via --dns  
- Automatic SSH root login configuration  
- Custom SSH port support with reliable fallback injection  
- Automatic random root password generation when -p is not provided  
- Password validation to prevent shell-unsafe characters  
- Built-in FQ and BBR network optimization  
- Ubuntu cloud image integrity verification  
- Ubuntu EFI fallback boot path repair  
- CentOS 7 Vault fallback for legacy dependency installation  
- Interactive confirmation prompt before disk erasure  
- Root privilege and architecture pre-checks  
- Idempotent GRUB configuration  

---

## Supported Operating Systems

Debian:  
- Debian 13 (Trixie)  
- Debian 12 (Bookworm) — default  
- Debian 11 (Bullseye)  

Ubuntu:  
- Ubuntu 24.04 LTS (Noble) — default  
- Ubuntu 22.04 LTS (Jammy)  

---

## Installation Architecture

Debian path:  
1. Pre-check root privilege and x86_64 architecture  
2. Detect current disk and network configuration  
3. Confirm with operator before proceeding  
4. Download official Debian netboot installer  
5. Inject preseed configuration and post-install script into initrd  
6. Create a temporary GRUB boot entry  
7. Reboot into the automated Debian installer  

Ubuntu path:  
1. Pre-check root privilege and x86_64 architecture  
2. Detect current disk and network configuration  
3. Confirm with operator before proceeding  
4. Download official Ubuntu cloud image and verify integrity  
5. Mount the image through qemu-nbd  
6. Configure root password, SSH, sysctl, netplan, cloud-init seed, and DNS  
7. Repair EFI fallback boot path if needed  
8. Write the image directly to the target disk  
9. Reboot into the new system  

---

## Parameters

| Parameter | Description |
|---|---|
| `-d [11\|12\|13]` | Install Debian (default: 12) |
| `-u [22\|24]` | Install Ubuntu (default: 24) |
| `-p PASSWORD` | Set root password |
| `-port PORT`, `--port PORT` | Set SSH port (default: 22) |
| `--dns "IP1 IP2"` | Set DNS servers (default: 8.8.8.8 8.8.4.4) |
| `-f`, `--force` | Skip confirmation prompt |
| `-v`, `--version` | Show version info |
| `-h`, `--help` | Show help |

---

## Password Rules

If `-p` is not provided, a 20-character random password is generated automatically.

Allowed characters: `A-Z a-z 0-9 ! @ # % ^ * _ + = . -`

Characters that could interfere with shell expansion or preseed parsing are rejected:  
`` $ ` " ' \ spaces ( ) { } | & ; < > ~ ``

---

## Default Behavior

- A confirmation prompt is displayed before any destructive action (skip with `--force`)  
- If -p is not provided, a random root password is generated automatically  
- The generated password is displayed before reboot and must be saved by the operator  
- SSH is configured to allow root login and password authentication  
- The detected primary disk is used as the installation target  
- Current network settings are reused for static configuration  
- Default DNS servers are 8.8.8.8 and 8.8.4.4 unless overridden  
- If --dns is provided, those DNS servers are written into the installed system  

---

## Network Configuration

Debian:  
OsNova installs a static systemd-networkd configuration using the detected IPv4 settings, optional IPv6 settings, and the selected DNS servers. IPv4 /32 and IPv6 /128 prefixes are handled with GatewayOnLink routing.

Ubuntu:  
OsNova installs a static netplan configuration rendered by systemd-networkd, disables cloud-init network generation, and writes the selected DNS servers into the installed system. IPv4 /32 and IPv6 /128 prefixes are handled with on-link routing.

---

## Tested Environments

- KVM virtual machines  
- Common cloud VPS providers  
- BIOS systems  
- UEFI systems  

---

## Intended Use

OsNova is intended for:  

- VPS reprovisioning  
- Bare-metal operating system replacement  
- Clean system redeployment  
- Infrastructure rebuild workflows  
- Deterministic Debian and Ubuntu reinstall operations  

It is not designed as a rescue panel replacement or a consumer desktop installer.  

---

## Changelog

### v2.2.0

- Fixed Debian installer hang at "Loading additional components / Retrieving *.udeb" by adding an explicit mirror block (`mirror/http/hostname`, `directory`, `suite`) to both the preseed and the kernel command line — previously no mirror was specified, so the installer had no host to fetch udebs from
- Fixed `netcfg/get_nameservers` passing a space-separated DNS list (d-i treats it as a single token, breaking udeb-stage DNS); the installer now uses the first DNS, while the full list is still written into the installed system
- Added `netcfg/get_hostname` and `netcfg/get_domain` to prevent hidden prompts when DNS is unstable
- Made `preseed/late_command` robust: searches multiple known locations for `post-install.sh`, uses `&&` chaining so failures surface, and logs to `/var/log/osnova-postinstall.log` in the target system
- post-install.sh is now staged in multiple initrd locations so it survives regardless of d-i build layout
- Added `partman/early_command` to wipe pre-existing LVM/MD/partition signatures (`vgchange`, `pvremove`, `mdadm --stop`, `wipefs`) plus `partman-lvm/device_remove_lvm` and `partman-md/device_remove_md`, preventing silent partitioner hangs on previously-provisioned disks
- Switched GRUB default selection to the canonical `GRUB_DEFAULT=saved` + `grub-set-default`/`grub-reboot` method and forced `GRUB_DISABLE_SUBMENU=y`, so the installer entry boots reliably even when GRUB builds a submenu
- No user-facing CLI changes — fully compatible with v2.1.0 invocation

### v2.1.0

- Fixed network detection on hosts with multi-IP interfaces (cloud VPS with main IP + alias addresses)
- Fixed mixed IPv4/IPv6 default routes pointing at different interfaces (`ip -4` / `ip -6` now used explicitly)
- Fixed disk detection to use awk exact-equality on the TYPE column instead of substring match
- Added wget `--tries=3 --timeout=30/60` to both Debian netboot and Ubuntu cloud image downloads
- Added qcow2 format pre-check via `qemu-img info` (catches HTML error pages saved as `.img`)
- Ubuntu image download no longer uses `--continue` — stale images from a different release URL are removed first
- Added IPv4 default-route guard: script now aborts cleanly if no default route is detected
- Added qemu-nbd settle delay between disconnect and connect
- Refactored systemd-networkd IPv6 block to use a single pre-built string instead of nested heredoc-in-command-substitution
- No user-facing CLI changes — fully compatible with v2.0.0 invocation

### v2.0.0

- Added root privilege and x86_64 architecture pre-checks  
- Added interactive confirmation prompt before disk erasure (`--force` to skip)  
- Added `--version` / `-v` parameter  
- Added password validation to reject shell-unsafe characters  
- Upgraded random password generation to 20 characters with symbols  
- Fixed preseed password injection to prevent shell expansion issues  
- Fixed SSH port configuration to reliably write Port even when missing from sshd_config  
- Fixed GRUB_DISABLE_OS_PROBER repeated append (now idempotent)  
- Fixed disk detection fallback to exclude loop, nbd, ram, and zram devices  
- Added Ubuntu cloud image integrity verification via qemu-img check  
- Added IPv6 /128 on-link route support for both Debian and Ubuntu paths  
- Improved cleanup trap to cover HUP/PIPE signals and temporary work directory  
- Debian BBR configuration moved to dedicated sysctl.d file  
- Debian SSH configuration now uses sshd_config.d override for reliability  

### v1.0.0

- Initial release  

---

## License

GPL-3.0  

OsNova is distributed under GPL-3.0.  
All components comply with upstream licensing requirements of the Linux ecosystem.

---

## Philosophy

Minimal assumptions. Direct execution. Reproducible results.
---

Part of the [Nova infrastructure toolkit](https://github.com/harryheros).
