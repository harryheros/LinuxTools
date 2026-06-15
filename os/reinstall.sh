#!/usr/bin/env bash
# ==============================================================================
# Project: OsNova - System Deployment & Reinstallation Engine
# Version: 2.2.0
# Description: BIOS + UEFI compatible automated network installer
#              for Debian and Ubuntu systems on VPS and bare-metal servers.
#
# Author: Harry
# GitHub: https://github.com/harryheros/osnova
# Copyright (C) 2026 Harry
#
# License: GNU General Public License v3.0 (GPL-3.0)
# ==============================================================================

set -e

# --- Color and Formatting ---
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

# --- Defaults ---
OS_TYPE="debian"
RELEASE=""
SSH_PORT="22"
ROOT_PASS=""
VERSION="2.2.0"
PASSWORD_WAS_GENERATED=0
DNS_SERVERS="8.8.8.8 8.8.4.4"
FORCE_MODE=0
IPV6_USABLE=1

generate_random_password() {
    tr -dc 'A-Za-z0-9!@#%^*_+=' </dev/urandom | head -c 20
}

# --- Help ---
show_help() {
    echo -e "${CYAN}OsNova v${VERSION} - System Deployment & Reinstallation Engine${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  bash reinstall.sh [options]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${YELLOW}-d [11|12|13]${NC}           Install Debian (default: 12)"
    echo -e "  ${YELLOW}-u [22|24]${NC}              Install Ubuntu (default: 24)"
    echo -e "  ${YELLOW}-p PASSWORD${NC}             Set root password (optional)"
    echo -e "  ${YELLOW}-port PORT, --port PORT${NC} Set SSH port (default: 22)"
    echo -e "  ${YELLOW}--dns \"IP1 IP2\"${NC}         Set DNS servers (default: 8.8.8.8 8.8.4.4)"
    echo -e "  ${YELLOW}-f, --force${NC}             Skip confirmation prompt"
    echo -e "  ${YELLOW}-v, --version${NC}           Show version info"
    echo -e "  ${YELLOW}-h, --help${NC}              Show this help"
    echo ""
    echo -e "${BOLD}Notes:${NC}"
    echo -e "  • If ${YELLOW}-p${NC} is not provided, a random root password will be generated."
    echo -e "  • The generated password will be shown before reboot."
    echo -e "  • Password may only contain: A-Z a-z 0-9 !@#%^*_+="
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  bash reinstall.sh"
    echo -e "  bash reinstall.sh -d 13"
    echo -e "  bash reinstall.sh -u"
    echo -e "  bash reinstall.sh -u 22"
    echo -e "  bash reinstall.sh -u 24 -p mypass --port 2222"
    echo -e "  bash reinstall.sh -u 24 -p mypass --port 2222 --force"
}

show_version() {
    echo -e "${CYAN}OsNova v${VERSION}${NC}"
    echo -e "GitHub: https://github.com/harryheros/osnova"
    echo -e "Copyright (C) 2026 Harry"
    echo -e "License: GPL-3.0"
}

# ==============================================================================
# ENVIRONMENT PRE-CHECKS
# ==============================================================================
check_env() {
    # 1. Root privilege check
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        echo -e "${YELLOW}Hint: Use 'sudo bash reinstall.sh' or run as root user.${NC}"
        exit 1
    fi

    # 2. Architecture check (all images are amd64)
    local arch
    arch="$(uname -m)"
    if [ "$arch" != "x86_64" ]; then
        echo -e "${RED}Error: Unsupported architecture '${arch}'.${NC}"
        echo -e "${YELLOW}OsNova only supports x86_64 (amd64) systems.${NC}"
        exit 1
    fi
}

# --- Password validation (safe characters only) ---
validate_password() {
    local pass="$1"
    if [ -z "$pass" ]; then
        echo -e "${RED}Error: Password cannot be empty.${NC}"; exit 1
    fi
    # Allow: A-Z a-z 0-9 and a safe set of symbols
    # Reject anything that could break shell/heredoc/preseed: $ ` " ' \ spaces newlines ( ) { } | & ; < > ~
    if ! echo "$pass" | grep -qP '^[A-Za-z0-9!@#%^*_+=.-]+$'; then
        echo -e "${RED}Error: Password contains unsupported characters.${NC}"
        echo -e "${YELLOW}Allowed characters: A-Z a-z 0-9 ! @ # % ^ * _ + = . -${NC}"
        echo -e "${YELLOW}Characters NOT allowed: \$ \` \" ' \\ spaces ( ) { } | & ; < > ~${NC}"
        exit 1
    fi
}

# --- Argument Parsing ---
DEBIAN_SET=0
UBUNTU_SET=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d)
            if [ "$UBUNTU_SET" -eq 1 ]; then
                echo -e "${RED}Error: Cannot use -d and -u together.${NC}"; exit 1
            fi
            DEBIAN_SET=1; OS_TYPE="debian"
            if [[ "$2" =~ ^(11|12|13)$ ]]; then RELEASE="$2"; shift 2
            elif [[ -z "$2" || "$2" == -* ]]; then RELEASE="12"; shift 1
            else
                echo -e "${RED}Error: Unsupported Debian version '$2'. (Available: 11, 12, 13)${NC}"; exit 1
            fi
            ;;
        -u)
            if [ "$DEBIAN_SET" -eq 1 ]; then
                echo -e "${RED}Error: Cannot use -d and -u together.${NC}"; exit 1
            fi
            UBUNTU_SET=1; OS_TYPE="ubuntu"
            if [[ "$2" =~ ^(22|24)$ ]]; then RELEASE="$2"; shift 2
            elif [[ -z "$2" || "$2" == -* ]]; then RELEASE="24"; shift 1
            else
                echo -e "${RED}Error: Unsupported Ubuntu version '$2'. (Available: 22, 24)${NC}"; exit 1
            fi
            ;;
        -p)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Password cannot be empty.${NC}"; exit 1
            fi
            ROOT_PASS="$2"; shift 2
            ;;
        -port|--port)
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ]; then
                SSH_PORT="$2"; shift 2
            else
                echo -e "${RED}Error: Invalid port number '$2' (1-65535)${NC}"; exit 1
            fi
            ;;
        --dns)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo -e "${RED}Error: DNS cannot be empty.${NC}"; exit 1
            fi
            DNS_SERVERS="$(echo "$2" | tr ',' ' ')"
            shift 2
            ;;
        -f|--force)
            FORCE_MODE=1; shift 1
            ;;
        -v|--version)
            show_version; exit 0
            ;;
        -h|--help)
            show_help; exit 0
            ;;
        *)
            echo -e "${RED}Error: Invalid option '$1'${NC}"
            echo -e "${YELLOW}Hint: Use -d for Debian, -u for Ubuntu, -p for password, --port for SSH port.${NC}"
            exit 1
            ;;
    esac
done

# --- Run environment checks (root, arch) ---
check_env

if [ "$OS_TYPE" = "debian" ] && [ -z "$RELEASE" ]; then RELEASE="12"; fi
if [ "$OS_TYPE" = "ubuntu" ] && [ -z "$RELEASE" ]; then RELEASE="24"; fi

# --- Password handling ---
if [ -n "$ROOT_PASS" ]; then
    validate_password "$ROOT_PASS"
else
    ROOT_PASS="$(generate_random_password)"
    PASSWORD_WAS_GENERATED=1
fi

clear
echo -e "${CYAN}"
cat << "ASCIIEOF"
   ____  _____ _   __                 
  / __ \/ ___// | / /___ _   ______ _ 
 / / / /\__ \/  |/ / __ \ | / / __ `/ 
/ /_/ /___/ / /|  / /_/ / |/ / /_/ /  
\____//____/_/ |_/\____/|___/\__,_/   
 >> System Deployment & Reinstallation Engine <<
ASCIIEOF
echo -e "${NC}"
echo -e "${CYAN}❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊${NC}"
echo -e "${GREEN}${BOLD}               OsNova Deployment Engine v${VERSION}${NC}"
echo -e "${GREEN}                     Copyright (C) 2026 Harry${NC}"
echo -e "${CYAN}❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊${NC}"

if [ "$PASSWORD_WAS_GENERATED" -eq 1 ]; then
    echo -e "\n${YELLOW}${BOLD}No root password was provided.${NC}"
    echo -e "${YELLOW}A random password has been generated for this installation:${NC}"
    echo -e "${GREEN}${BOLD}${ROOT_PASS}${NC}"
    echo -e "${RED}${BOLD}Please save this password now. It will be required after installation.${NC}"
fi

echo -e "\n${BOLD}${CYAN}Step: Pre-installing essential tools...${NC}"
export DEBIAN_FRONTEND=noninteractive

IS_CENTOS7=0
if [ -f /etc/centos-release ] && grep -q "CentOS Linux release 7" /etc/centos-release; then
    IS_CENTOS7=1
    echo -e "${YELLOW}CentOS 7 detected (EOL). Ensuring Vault 7.9.2009 repo is available...${NC}"
    cat >/etc/yum.repos.d/osnova-vault-7.9.2009.repo <<'VAULTEOF'
[osnova-vault-base]
name=OsNova Vault 7.9.2009 - Base
baseurl=http://vault.centos.org/7.9.2009/os/$basearch/
enabled=1
gpgcheck=0

[osnova-vault-updates]
name=OsNova Vault 7.9.2009 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=0

[osnova-vault-extras]
name=OsNova Vault 7.9.2009 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=0
VAULTEOF
    yum clean all >/dev/null 2>&1 || true
fi

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y curl util-linux wget ca-certificates kexec-tools tar gzip cpio \
        grub2-common cloud-guest-utils e2fsprogs qemu-utils gdisk
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl util-linux wget ca-certificates kexec-tools tar gzip cpio qemu-img gdisk \
        grub2 grub2-tools cloud-utils-growpart e2fsprogs
    [ ! -f /usr/sbin/grub-probe ] && [ -f /usr/sbin/grub2-probe ] && \
        ln -sf /usr/sbin/grub2-probe /usr/sbin/grub-probe
elif command -v yum >/dev/null 2>&1; then
    if [ "$IS_CENTOS7" -eq 1 ]; then
        yum --disablerepo="*" --enablerepo="osnova-vault-*" install -y \
            curl util-linux wget ca-certificates kexec-tools tar gzip cpio \
            grub2 grub2-tools cloud-utils-growpart e2fsprogs
    else
        yum install -y curl util-linux wget ca-certificates kexec-tools tar gzip cpio \
            grub2 grub2-tools cloud-utils-growpart e2fsprogs
    fi
    [ ! -f /usr/sbin/grub-probe ] && [ -f /usr/sbin/grub2-probe ] && \
        ln -sf /usr/sbin/grub2-probe /usr/sbin/grub-probe
else
    echo -e "${RED}Error: Package manager not found. Please install wget manually.${NC}"; exit 1
fi

echo -e "\n${BOLD}${CYAN}Step: Detecting environment and network...${NC}"

# --- Cleanup trap ---
cleanup() {
    umount /tmp/img_root_mnt 2>/dev/null || true
    umount /tmp/efi_fix_mnt  2>/dev/null || true
    qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
    # Clean temporary work directory
    rm -rf /var/tmp/osnova 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP PIPE

# --- Disk Detection ---
REAL_DISK=""
if [ -d /sys/block ]; then
    for dev in $(ls /sys/block | grep -E '^(sd|vd|nvme|hd)'); do
        if [ -f "/sys/block/$dev/removable" ] && [ "$(cat /sys/block/$dev/removable)" = "0" ]; then
            REAL_DISK="/dev/$dev"; break
        fi
    done
fi
if [ -z "$REAL_DISK" ] && command -v lsblk >/dev/null; then
    # Use awk's exact-equality filter instead of grep substring match,
    # so a device name that happens to contain "disk" (extremely unlikely
    # but theoretically possible) can't false-match the TYPE column.
    # Exclude loop, nbd, ram, zram — these are not installation targets.
    REAL_DISK="/dev/$(lsblk -dn -o NAME,TYPE | awk '$2=="disk" && $1 !~ /^(loop|nbd|ram|zram)/ {print $1; exit}')"
    # Validate we actually got something useful
    if [ "$REAL_DISK" = "/dev/" ] || [ -z "$REAL_DISK" ]; then
        REAL_DISK=""
    fi
fi
if [ -z "$REAL_DISK" ]; then
    REAL_DISK="/dev/sda"
    echo -e "${YELLOW}Warning: Disk auto-detection failed, defaulting to /dev/sda${NC}"
    echo -e "${YELLOW}If this is wrong, press Ctrl+C within 10 seconds to abort.${NC}"
    sleep 10
fi

# --- Network Detection ---
# Use ip -4 / ip -6 explicitly so an IPv6-only default route on a different
# interface can't displace the IPv4 default. head -n1 on every variable
# guards against multi-IP NICs (cloud VPS routinely have a main address
# plus aliases) — without head, ${V_IP}/${V_PREFIX} would be e.g.
# "1.2.3.4 5.6.7.8/32" and break every downstream config file.
INTERFACE=$(ip -4 route show default | awk '{print $5; exit}')
if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Error: No IPv4 default route detected. Cannot continue.${NC}"
    echo -e "${YELLOW}Hint: verify the system has working IPv4 connectivity before running OsNova.${NC}"
    exit 1
fi

V_IP=$(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2; exit}' | cut -d/ -f1)
V_PREFIX=$(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2; exit}' | cut -d/ -f2)
V_GATEWAY=$(ip -4 route show default | awk '{print $3; exit}')

if [ -z "$V_IP" ] || [ -z "$V_PREFIX" ] || [ -z "$V_GATEWAY" ]; then
    echo -e "${RED}Error: Could not determine IPv4 configuration for ${INTERFACE}.${NC}"
    echo -e "${YELLOW}Detected: IP='${V_IP}' prefix='${V_PREFIX}' gw='${V_GATEWAY}'${NC}"
    exit 1
fi

# IPv6 detection (optional — not all VPS have IPv6). Same head-n1 hygiene.
V_IP6=$(ip -6 addr show "$INTERFACE" | awk '/inet6 / && !/fe80/ {print $2; exit}' | cut -d/ -f1)
V_PREFIX6=$(ip -6 addr show "$INTERFACE" | awk '/inet6 / && !/fe80/ {print $2; exit}' | cut -d/ -f2)
V_GATEWAY6=$(ip -6 route show default | awk '{print $3; exit}')

# IPv6 reachability validation. Some VPS (common on budget providers) hand out
# an IPv6 address and even a default route that does NOT actually work — the
# upstream simply doesn't route IPv6. Detecting the address alone is not enough:
# if we carry a half-broken IPv6 into the install, the Debian netboot installer
# tries the AAAA record of deb.debian.org when fetching udebs, times out, and
# stalls at a random "Retrieving *-udeb" step. We therefore probe actual
# connectivity and DISABLE IPv6 entirely if it fails — degrading cleanly to
# IPv4-only. Machines with working IPv6 keep full dual-stack; IPv4-only machines
# are unaffected.
if [ -n "$V_IP6" ] && [ -n "$V_GATEWAY6" ]; then
    # Only trust the probe if a v6-capable ping tool actually exists; otherwise
    # a missing tool would falsely "fail" the test and wrongly disable working
    # IPv6. If no tool is available, keep the old behavior (assume usable).
    if command -v ping6 >/dev/null 2>&1 || command -v ping >/dev/null 2>&1; then
        # Try gateway first (fast, local), then a public anycast as a second chance.
        if ping6 -c1 -W2 "$V_GATEWAY6" >/dev/null 2>&1 \
           || ping -6 -c1 -W2 "$V_GATEWAY6" >/dev/null 2>&1 \
           || ping6 -c1 -W3 2606:4700:4700::1111 >/dev/null 2>&1 \
           || ping -6 -c1 -W3 2606:4700:4700::1111 >/dev/null 2>&1; then
            : # IPv6 works — keep it
        else
            echo -e "${YELLOW}IPv6 address detected but not reachable — disabling IPv6 (IPv4-only install).${NC}"
            V_IP6=""; V_PREFIX6=""; V_GATEWAY6=""
            IPV6_USABLE=0
        fi
    fi
fi

prefix_to_mask() {
    local i mask=""
    local full_octets=$(($1 / 8))
    local partial_octet=$(($1 % 8))
    for ((i=0; i<4; i++)); do
        if [ $i -lt $full_octets ]; then mask+="255"
        elif [ $i -eq $full_octets ]; then mask+=$((256 - 2**(8-partial_octet)))
        else mask+="0"; fi
        [ $i -lt 3 ] && mask+="."
    done
    echo "$mask"
}
V_NETMASK=$(prefix_to_mask "$V_PREFIX")

# --- Resolve display names ---
if [ "$OS_TYPE" = "debian" ]; then
    case "$RELEASE" in
        "11") REL_NAME="bullseye" ;;
        "12") REL_NAME="bookworm" ;;
        *)    REL_NAME="trixie"   ;;
    esac
    DISPLAY_NAME="Debian ${RELEASE} (${REL_NAME})"
else
    case "$RELEASE" in
        "22") REL_NAME="jammy"; FULL_VER="22.04" ;;
        *)    REL_NAME="noble"; FULL_VER="24.04" ;;
    esac
    DISPLAY_NAME="Ubuntu ${FULL_VER} (${REL_NAME})"
fi

echo -e "      Target OS : ${YELLOW}${DISPLAY_NAME}${NC}"
echo -e "      Root Disk : ${YELLOW}${REAL_DISK}${NC}"
echo -e "      IP Config : ${YELLOW}${V_IP} / ${V_NETMASK}${NC}"

# ==============================================================================
# CONFIRMATION PROMPT (skip with --force / -f)
# ==============================================================================
if [ "$FORCE_MODE" -eq 0 ]; then
    echo ""
    echo -e "${RED}${BOLD}WARNING: This will ERASE ALL DATA on ${REAL_DISK} and reinstall ${DISPLAY_NAME}.${NC}"
    echo -e "${RED}${BOLD}This action is irreversible.${NC}"
    echo ""
    echo -ne "${YELLOW}Type 'yes' to continue, or anything else to abort: ${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${CYAN}Aborted. No changes were made.${NC}"
        exit 0
    fi
fi

WORKDIR="/var/tmp/osnova"
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"

# ==============================================================================
# DEBIAN INSTALLATION PATH
# ==============================================================================
install_debian() {
    echo -e "\n${BOLD}${CYAN}Step: Fetching Debian network installer...${NC}"

    MIRROR="https://deb.debian.org/debian/dists/${REL_NAME}/main/installer-amd64/current/images/netboot/"
    # --tries=3 --timeout=30: transient hiccups (mirror DNS jitter, brief TLS
    # reset) shouldn't force the operator to restart the entire reinstall.
    wget --tries=3 --timeout=30 -O "${WORKDIR}/netboot.tar.gz" "${MIRROR}netboot.tar.gz"

    # Determine if /32 prefix requires GatewayOnLink
    if [ "$V_PREFIX" = "32" ]; then
        NETWORKD_GATEWAY=""
        NETWORKD_ROUTE_EXTRA="
[Route]
Destination=0.0.0.0/0
Gateway=${V_GATEWAY}
GatewayOnLink=yes"
    else
        NETWORKD_GATEWAY="Gateway=${V_GATEWAY}"
        NETWORKD_ROUTE_EXTRA=""
    fi

    # IPv6 block (computed entirely here, then dropped verbatim into the
    # systemd-networkd config via a single heredoc — much easier to read
    # than the previous nested heredoc-inside-command-substitution form,
    # and uses the outer script's V_IP6/V_PREFIX6/V_GATEWAY6 directly
    # without needing the post-install stage to re-resolve them).
    NETWORKD_IPV6_BLOCK=""
    if [ -n "$V_IP6" ] && [ -n "$V_PREFIX6" ]; then
        NETWORKD_IPV6_BLOCK="
[Address]
Address=${V_IP6}/${V_PREFIX6}"
        if [ -n "$V_GATEWAY6" ]; then
            if [ "$V_PREFIX6" = "128" ]; then
                NETWORKD_IPV6_BLOCK="${NETWORKD_IPV6_BLOCK}

[Route]
Gateway=${V_GATEWAY6}
Destination=::/0
GatewayOnLink=yes"
            else
                NETWORKD_IPV6_BLOCK="${NETWORKD_IPV6_BLOCK}

[Route]
Gateway=${V_GATEWAY6}
Destination=::/0"
            fi
        fi
    fi

    cat > "${WORKDIR}/post-install.sh" <<POSTINSTALL
#!/bin/sh
set -e

# --- SSH config ---
# Primary mechanism: a sshd_config.d drop-in (Debian 12+/Ubuntu read these via
# the Include at the top of sshd_config, and first-match-wins means our values
# take effect). chmod 644 is REQUIRED — sshd refuses to load a drop-in that is
# group/other-writable and silently ignores it.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-osnova.conf <<'SSHEOF'
PermitRootLogin yes
PasswordAuthentication yes
Port ${SSH_PORT}
SSHEOF
chmod 644 /etc/ssh/sshd_config.d/99-osnova.conf

# Fallback: also patch the main config for systems without an Include line.
# Guarded with a file-existence test and || true so that a missing or unusual
# main config can never abort this script under set -e (which would otherwise
# skip the BBR/network steps below).
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config || true
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config || true
    if grep -qE '^#?\s*Port\s' /etc/ssh/sshd_config; then
        sed -i 's/^#\?\s*Port\s.*/Port ${SSH_PORT}/g' /etc/ssh/sshd_config || true
    else
        echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
    fi
fi

# Debian ships ssh as socket-activated (ssh.socket), whose ListenStream=22
# OVERRIDES the Port in sshd_config — so a custom port silently fails to take
# effect. Disable the socket unit and fall back to the classic ssh.service so
# the configured Port is the one that listens. Guarded for chroot (no running
# systemd) and for systems that don't use the socket.
if [ -e /lib/systemd/system/ssh.socket ] || [ -e /etc/systemd/system/ssh.socket ]; then
    systemctl disable ssh.socket 2>/dev/null || true
    rm -f /etc/systemd/system/ssh.service.requires/ssh.socket 2>/dev/null || true
fi
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true

# --- BBR ---
cat > /etc/sysctl.d/99-osnova-bbr.conf <<'BBREOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
BBREOF

# --- Network: systemd-networkd with Type=ether ---
# Matches all physical ethernet NICs regardless of naming scheme
# (eth0, ens18, enp6s18, etc.) — no net.ifnames hacks needed
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-static.network <<EOF
[Match]
Type=ether

[Network]
Address=${V_IP}/${V_PREFIX}
${NETWORKD_GATEWAY}
$(echo "${DNS_SERVERS}" | tr ' ' '\n' | sed 's/^/DNS=/')
${NETWORKD_ROUTE_EXTRA}
${NETWORKD_IPV6_BLOCK}
EOF

# Enable systemd-networkd, disable legacy networking
# In the d-i chroot there is no running systemd/D-Bus, so these can return
# non-zero even when the symlink is created correctly. Guard with || true so
# set -e does not abort the script (which would skip the steps below).
systemctl enable systemd-networkd 2>/dev/null || true
systemctl disable networking 2>/dev/null || true

# Disable /etc/network/interfaces to avoid conflict
printf '# Managed by systemd-networkd\n# See /etc/systemd/network/\n' > /etc/network/interfaces

# Ensure all writes are flushed to disk before reboot
sync
POSTINSTALL
    chmod +x "${WORKDIR}/post-install.sh"

    cat > "${WORKDIR}/preseed.cfg" <<'PRESEEDEOF'
d-i debconf/priority string critical
d-i auto-install/enable boolean true
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean true
d-i hw-detect/load_firmware boolean false
PRESEEDEOF

    # Append network and disk config (these contain variables, use expanding heredoc)
    # NOTE: netcfg/get_nameservers must be a SINGLE address for d-i — a
    # space-separated list breaks udeb-stage DNS resolution (the installer
    # uses it verbatim as one token). Use the first DNS for the installer;
    # the full DNS_SERVERS list is still written into the final system by
    # post-install.sh. The mirror/* block is REQUIRED: without it the
    # installer stalls at "Loading additional components / Retrieving *.udeb"
    # because it has no mirror host to fetch udebs from.
    FIRST_DNS=$(echo "${DNS_SERVERS}" | awk '{print $1}')
    cat >> "${WORKDIR}/preseed.cfg" <<EOF
d-i netcfg/get_ipaddress string ${V_IP}
d-i netcfg/get_netmask string ${V_NETMASK}
d-i netcfg/get_gateway string ${V_GATEWAY}
d-i netcfg/get_nameservers string ${FIRST_DNS}
d-i netcfg/confirm_static boolean true
d-i netcfg/get_hostname string debian
d-i netcfg/get_domain string localdomain
d-i netcfg/hostname string debian

d-i mirror/country string manual
d-i mirror/protocol string http
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i mirror/suite string ${REL_NAME}
d-i apt-setup/use_mirror boolean true

tasksel tasksel/first multiselect standard, ssh-server
# Belt-and-suspenders: explicitly include openssh-server. The ssh-server
# tasksel entry can be skipped on some mirrors/releases, which would leave the
# box with no sshd at all — sshd_config edits then apply to nothing and the
# host is unreachable. pkgsel/include guarantees the package is installed.
d-i pkgsel/include string openssh-server
d-i pkgsel/upgrade select none

# Wipe any pre-existing LVM/MD/partition signatures BEFORE partman scans the
# disk. On VPS that were previously provisioned with LVM or software RAID,
# partman otherwise stops to ask about active volume groups / md arrays —
# a prompt that priority=critical cannot auto-answer, causing a silent hang.
d-i partman/early_command string \
    disk="${REAL_DISK}"; \
    vgchange -an 2>/dev/null || true; \
    for v in \$(pvs --noheadings -o pv_name 2>/dev/null | grep "\$disk"); do pvremove -ff -y "\$v" 2>/dev/null || true; done; \
    mdadm --stop --scan 2>/dev/null || true; \
    wipefs -a "\$disk" 2>/dev/null || true

d-i partman-auto/disk string ${REAL_DISK}
d-i partman-auto/method string regular
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string ${REAL_DISK}

d-i passwd/make-user boolean false
EOF

    # Append password lines using printf to avoid any shell expansion issues
    printf 'd-i passwd/root-password password %s\n' "${ROOT_PASS}" >> "${WORKDIR}/preseed.cfg"
    printf 'd-i passwd/root-password-again password %s\n' "${ROOT_PASS}" >> "${WORKDIR}/preseed.cfg"

    cat >> "${WORKDIR}/preseed.cfg" <<'PRESEEDTAILEOF'
d-i finish-install/reboot_in_progress note

# late_command runs in the d-i environment (not the target). We search a few
# known locations for post-install.sh because where it survives depends on the
# d-i build: initrd root (/), the preseed dir, or /var/lib/preseed. Chaining
# with && (not ;) so a copy/run failure is visible in /var/log/syslog rather
# than silently rebooting into a half-configured network. All output is logged
# to the target so it can be inspected post-boot if SSH still fails.
d-i preseed/late_command string \
    for p in /post-install.sh /cdrom/post-install.sh /preseed/post-install.sh /var/lib/preseed/post-install.sh; do \
        if [ -f "\$p" ]; then cp "\$p" /target/tmp/post-install.sh; break; fi; \
    done; \
    in-target chmod +x /tmp/post-install.sh; \
    in-target /tmp/post-install.sh; \
    sync; sleep 3
PRESEEDTAILEOF

    cd "$WORKDIR" && tar -xzf netboot.tar.gz
    mkdir -p initrd_work && cd initrd_work
    gzip -dc "../debian-installer/amd64/initrd.gz" | cpio -idmu >/dev/null 2>&1
    cp "${WORKDIR}/preseed.cfg" ./preseed.cfg
    # Place post-install.sh in several locations the late_command searches,
    # so it survives regardless of how this d-i build lays out its root.
    cp "${WORKDIR}/post-install.sh" ./post-install.sh
    mkdir -p ./preseed && cp "${WORKDIR}/post-install.sh" ./preseed/post-install.sh
    chmod +x ./post-install.sh ./preseed/post-install.sh

    rm -f /boot/vmlinuz-*osnova /boot/initrd-*osnova.gz 2>/dev/null
    find . | cpio -H newc -o 2>/dev/null | gzip -1 > /boot/initrd-debian${RELEASE}-osnova.gz
    cp "${WORKDIR}/debian-installer/amd64/linux" /boot/vmlinuz-debian${RELEASE}-osnova

    KERNEL_PATH="/boot/vmlinuz-debian${RELEASE}-osnova"
    INITRD_PATH="/boot/initrd-debian${RELEASE}-osnova.gz"
    FIRST_DNS=$(echo "${DNS_SERVERS}" | awk '{print $1}')
    NET_APPEND="netcfg/disable_autoconfig=true netcfg/get_ipaddress=${V_IP} netcfg/get_netmask=${V_NETMASK} netcfg/get_gateway=${V_GATEWAY} netcfg/get_nameservers=${FIRST_DNS} netcfg/confirm_static=true netcfg/get_hostname=debian netcfg/get_domain=localdomain"
    MIRROR_APPEND="mirror/http/hostname=deb.debian.org mirror/http/directory=/debian mirror/suite=${REL_NAME}"
    # If IPv6 was found unusable (address present but unreachable), disable it at
    # the kernel level for the installer. Otherwise d-i resolves deb.debian.org's
    # AAAA record, tries IPv6 to fetch udebs, times out, and stalls at a random
    # "Retrieving *-udeb" step. ipv6.disable=1 forces the whole udeb fetch over
    # IPv4. Working-IPv6 and IPv4-only machines never reach this branch.
    IPV6_APPEND=""
    if [ "$IPV6_USABLE" -eq 0 ]; then
        IPV6_APPEND="ipv6.disable=1"
    fi
    KERNEL_APPEND="auto=true priority=critical file=/preseed.cfg locale=en_US.UTF-8 keymap=us hostname=debian domain=localdomain ${NET_APPEND} ${MIRROR_APPEND} ${IPV6_APPEND} vga=788 --- quiet"
    GRUB_TITLE="OsNova-Debian${RELEASE}"
    UBUNTU_CLOUD=0
}

# ==============================================================================
# UBUNTU INSTALLATION PATH
# NBD mount → chroot config → EFI fix → disconnect → convert → reboot
# ==============================================================================
install_ubuntu() {
    echo -e "\n${BOLD}${CYAN}Step: Installing Ubuntu via QCOW2 Cloud Image...${NC}"
    case "$RELEASE" in
        22) IMG_URL="https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img" ;;
        *)  IMG_URL="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img" ;;
    esac

    IMG_PATH="/var/tmp/ubuntu-cloud.img"
    # Remove stale image from any previous run. --continue would otherwise
    # try to resume into a file from a different release URL, producing a
    # spliced binary that qemu-img check might or might not catch.
    rm -f "${IMG_PATH}"
    echo -e "${CYAN}Downloading Ubuntu cloud image (~600MB)...${NC}"
    wget --tries=3 --timeout=60 --show-progress -O "${IMG_PATH}" "${IMG_URL}"

    # Verify image integrity. Two-step:
    #   1. qemu-img info — confirms the file is parseable AND in qcow2 format.
    #      This guards against the upstream URL accidentally returning HTML
    #      (e.g. an HTTP 404 page wget happens to save), or a future Ubuntu
    #      release switching to raw images without us noticing.
    #   2. qemu-img check — verifies internal consistency of the qcow2 file.
    echo -e "${CYAN}Verifying image integrity...${NC}"
    if ! qemu-img info "${IMG_PATH}" 2>/dev/null | grep -q 'file format: qcow2'; then
        echo -e "${RED}Error: Downloaded file is not a qcow2 image.${NC}"
        echo -e "${YELLOW}Most likely an incomplete download or an HTML error page from the mirror.${NC}"
        rm -f "${IMG_PATH}"
        exit 1
    fi
    if ! qemu-img check "${IMG_PATH}" >/dev/null 2>&1; then
        echo -e "${RED}Error: Downloaded image failed integrity check.${NC}"
        echo -e "${YELLOW}The file may be corrupted or incomplete. Please try again.${NC}"
        rm -f "${IMG_PATH}"
        exit 1
    fi
    echo -e "${GREEN}Image integrity OK.${NC}"

    echo -e "${CYAN}Mounting QCOW2 image via NBD...${NC}"
    modprobe nbd max_part=16
    sleep 1
    # Disconnect first in case a previous OsNova attempt left /dev/nbd0
    # bound, then give the kernel a moment to release it before binding
    # again — sometimes a back-to-back disconnect/connect races and the
    # second qemu-nbd silently picks up stale state.
    qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
    sleep 1
    qemu-nbd --connect=/dev/nbd0 "${IMG_PATH}"
    sleep 2

    IMG_ROOT=$(lsblk -lnp -o NAME,FSTYPE,SIZE /dev/nbd0 2>/dev/null | grep "ext4" | sort -hk3 | tail -n1 | awk '{print $1}')
    IMG_EFI=$(lsblk -lnp -o NAME,FSTYPE /dev/nbd0 2>/dev/null | grep "vfat" | head -n1 | awk '{print $1}')
    echo -e "${CYAN}Root: ${IMG_ROOT} | EFI: ${IMG_EFI}${NC}"

    ROOT_MNT="/tmp/img_root_mnt"
    mkdir -p "${ROOT_MNT}"
    mount -t ext4 "${IMG_ROOT}" "${ROOT_MNT}"

    # 1. Root password (use chpasswd via chroot — safe for all character sets in validated passwords)
    echo "root:${ROOT_PASS}" | chroot "${ROOT_MNT}" chpasswd

    # 2. SSH — patch main config + write .d override
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "${ROOT_MNT}/etc/ssh/sshd_config"
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "${ROOT_MNT}/etc/ssh/sshd_config"
    # Handle Port: replace existing or append if missing
    if grep -qE '^#?\s*Port\s' "${ROOT_MNT}/etc/ssh/sshd_config"; then
        sed -i "s/^#\?\s*Port\s.*/Port ${SSH_PORT}/" "${ROOT_MNT}/etc/ssh/sshd_config"
    else
        echo "Port ${SSH_PORT}" >> "${ROOT_MNT}/etc/ssh/sshd_config"
    fi
    mkdir -p "${ROOT_MNT}/etc/ssh/sshd_config.d"
    rm -f "${ROOT_MNT}/etc/ssh/sshd_config.d/"*
    cat > "${ROOT_MNT}/etc/ssh/sshd_config.d/99-osnova.conf" <<EOF
PermitRootLogin yes
PasswordAuthentication yes
Port ${SSH_PORT}
EOF

    # 3. BBR
    cat > "${ROOT_MNT}/etc/sysctl.d/99-osnova-bbr.conf" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    # 4. Static netplan — type: ethernet match covers all physical NICs
    rm -f "${ROOT_MNT}/etc/netplan/"*.yaml

    # Build addresses and routes (handle /32 IPv4 and /128 IPv6 with on-link)
    if [ -n "$V_IP6" ] && [ -n "$V_PREFIX6" ] && [ -n "$V_GATEWAY6" ]; then
        NETPLAN_ADDRESSES="[${V_IP}/${V_PREFIX}, ${V_IP6}/${V_PREFIX6}]"
        # IPv4 route
        if [ "$V_PREFIX" = "32" ]; then
            NETPLAN_V4_ROUTE="{to: default, via: ${V_GATEWAY}, on-link: true}"
        else
            NETPLAN_V4_ROUTE="{to: default, via: ${V_GATEWAY}}"
        fi
        # IPv6 route
        if [ "$V_PREFIX6" = "128" ]; then
            NETPLAN_V6_ROUTE="{to: \"::/0\", via: \"${V_GATEWAY6}\", on-link: true}"
        else
            NETPLAN_V6_ROUTE="{to: \"::/0\", via: \"${V_GATEWAY6}\"}"
        fi
        NETPLAN_ROUTES="[${NETPLAN_V4_ROUTE}, ${NETPLAN_V6_ROUTE}]"
    else
        NETPLAN_ADDRESSES="[${V_IP}/${V_PREFIX}]"
        if [ "$V_PREFIX" = "32" ]; then
            NETPLAN_ROUTES="[{to: default, via: ${V_GATEWAY}, on-link: true}]"
        else
            NETPLAN_ROUTES="[{to: default, via: ${V_GATEWAY}}]"
        fi
    fi

    cat > "${ROOT_MNT}/etc/netplan/99-static-ip.yaml" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    all-interfaces:
      match:
        type: ethernet
      dhcp4: false
      dhcp6: false
      addresses: ${NETPLAN_ADDRESSES}
      routes: ${NETPLAN_ROUTES}
      nameservers: {addresses: [${DNS_SERVERS// /, }]}
EOF
    chmod 600 "${ROOT_MNT}/etc/netplan/99-static-ip.yaml"

    # 5. Disable cloud-init network generation
    mkdir -p "${ROOT_MNT}/etc/cloud/cloud.cfg.d"
    echo "network: {config: disabled}" > "${ROOT_MNT}/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"

    # 6. Cloud-init seed — only growpart/resize (dynamic disk name)
    REAL_DISK_BASE=$(basename "${REAL_DISK}")
    if echo "${REAL_DISK_BASE}" | grep -q "nvme"; then
        REAL_PART="${REAL_DISK}p1"
        REAL_PART_NUM="1"
    else
        REAL_PART="${REAL_DISK}1"
        REAL_PART_NUM="1"
    fi
    mkdir -p "${ROOT_MNT}/var/lib/cloud/seed/nocloud"
    cat > "${ROOT_MNT}/var/lib/cloud/seed/nocloud/meta-data" <<EOF
instance-id: i-$(date +%s)
local-hostname: ubuntu
EOF
    cat > "${ROOT_MNT}/var/lib/cloud/seed/nocloud/user-data" <<EOF
#cloud-config
runcmd:
  - growpart ${REAL_DISK} ${REAL_PART_NUM} || true
  - resize2fs ${REAL_PART} || true
EOF

    sync
    umount "${ROOT_MNT}"
    echo -e "${GREEN}Root filesystem configured!${NC}"

    # --- Fix EFI fallback path ---
    if [ -n "$IMG_EFI" ] && [ -b "$IMG_EFI" ]; then
        echo -e "${CYAN}Fixing EFI fallback path...${NC}"
        EFI_MNT="/tmp/efi_fix_mnt"
        mkdir -p "${EFI_MNT}"
        if mount -t vfat "${IMG_EFI}" "${EFI_MNT}" 2>/dev/null; then
            mkdir -p "${EFI_MNT}/EFI/BOOT"
            if [ -f "${EFI_MNT}/EFI/ubuntu/shimx64.efi" ]; then
                cp "${EFI_MNT}/EFI/ubuntu/shimx64.efi" "${EFI_MNT}/EFI/BOOT/BOOTX64.EFI"
                cp "${EFI_MNT}/EFI/ubuntu/grubx64.efi" "${EFI_MNT}/EFI/BOOT/grubx64.efi" 2>/dev/null || true
                echo -e "${GREEN}EFI/BOOT/BOOTX64.EFI written!${NC}"
            fi
            sync
            umount "${EFI_MNT}"
        fi
    fi

    qemu-nbd --disconnect /dev/nbd0
    sleep 1

    echo -e "${CYAN}Writing image to ${REAL_DISK}...${NC}"
    qemu-img convert -f qcow2 -O raw -p "${IMG_PATH}" "${REAL_DISK}"

    echo -e "${CYAN}Fixing GPT backup header...${NC}"
    sgdisk -e "${REAL_DISK}" 2>/dev/null || true
    partx -u "${REAL_DISK}" 2>/dev/null || true
    partprobe "${REAL_DISK}" 2>/dev/null || true

    echo -e "${GREEN}Ubuntu written to disk!${NC}"
    GRUB_TITLE=""
    UBUNTU_CLOUD=1
}

# --- Run installer ---
if [ "$OS_TYPE" = "debian" ]; then
    install_debian
else
    install_ubuntu
fi

# ==============================================================================
# GRUB CONFIGURATION (Debian only)
# ==============================================================================
if [ "$OS_TYPE" = "debian" ]; then
    echo -e "\n${BOLD}${CYAN}Step: Patching GRUB bootloader (Debian)...${NC}"

    BOOT_UUID=$(/usr/sbin/grub-probe --target=fs_uuid /boot 2>/dev/null || grub-probe --target=fs_uuid /boot)
    KERN_BN="$(basename "${KERNEL_PATH}")"
    INIT_BN="$(basename "${INITRD_PATH}")"
    cat > /etc/grub.d/40_custom <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry '${GRUB_TITLE}' {
    load_video
    insmod gzio
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
    if [ -f /boot/${KERN_BN} ]; then
        linux /boot/${KERN_BN} ${KERNEL_APPEND}
        initrd /boot/${INIT_BN}
    else
        linux /${KERN_BN} ${KERNEL_APPEND}
        initrd /${INIT_BN}
    fi
}
EOF
    chmod +x /etc/grub.d/40_custom

    # Selecting the default by menuentry TITLE only works when the entry is at
    # the top level. If GRUB builds a submenu (default on many distros), named
    # entries get nested and "GRUB_DEFAULT=title" silently fails — the box
    # boots the OLD kernel and the reinstall never starts. The canonical fix is
    # GRUB_DEFAULT=saved + grub-set-default, which resolves the title against
    # grubenv and works regardless of nesting. Also force top-level for safety.
    sed -i '/^GRUB_DEFAULT=/d' /etc/default/grub
    echo "GRUB_DEFAULT=saved" >> /etc/default/grub
    sed -i '/^GRUB_DISABLE_SUBMENU=/d' /etc/default/grub
    echo "GRUB_DISABLE_SUBMENU=y" >> /etc/default/grub
    sed -i '/^GRUB_TIMEOUT=/d' /etc/default/grub
    echo "GRUB_TIMEOUT=5" >> /etc/default/grub
    sed -i '/^GRUB_TIMEOUT_STYLE=/d' /etc/default/grub
    echo "GRUB_TIMEOUT_STYLE=menu" >> /etc/default/grub
    # Idempotent: remove existing line before appending
    sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    update-grub || grub2-mkconfig -o /boot/grub/grub.cfg

    # Now point the saved default at our entry by exact title. grub-set-default
    # writes grubenv, which GRUB_DEFAULT=saved reads at boot. Try persistent
    # set first, then grub-reboot as a one-shot guarantee for the next boot.
    if command -v grub-set-default >/dev/null 2>&1; then
        grub-set-default "${GRUB_TITLE}" 2>/dev/null || true
        grub-reboot "${GRUB_TITLE}" 2>/dev/null || true
    elif command -v grub2-set-default >/dev/null 2>&1; then
        grub2-set-default "${GRUB_TITLE}" 2>/dev/null || true
        grub2-reboot "${GRUB_TITLE}" 2>/dev/null || true
    fi
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "\n${CYAN}❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊${NC}"
echo -e "${GREEN}${BOLD}                   OsNova Deployment Summary${NC}"
echo -e "${CYAN}❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊${NC}"
echo -e "  OS       : ${YELLOW}${DISPLAY_NAME}${NC}"
echo -e "  Disk     : ${YELLOW}${REAL_DISK}${NC}"
echo -e "  IP       : ${YELLOW}${V_IP}/${V_PREFIX}${NC}"
echo -e "  Gateway  : ${YELLOW}${V_GATEWAY}${NC}"
[ -n "$V_IP6" ] && echo -e "  IPv6     : ${YELLOW}${V_IP6}/${V_PREFIX6}${NC}"
echo -e "  SSH Port : ${YELLOW}${SSH_PORT}${NC}"
echo -e "  DNS      : ${YELLOW}${DNS_SERVERS}${NC}"

if [ "$PASSWORD_WAS_GENERATED" -eq 1 ]; then
    echo -e "  Password : ${YELLOW}${ROOT_PASS}${NC} ${RED}(generated automatically — save it now)${NC}"
else
    echo -e "  Password : ${GREEN}(custom password set)${NC}"
fi

echo -e "${CYAN}❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊❊${NC}"

if [ "$PASSWORD_WAS_GENERATED" -eq 1 ]; then
    echo -e "\n${RED}${BOLD}IMPORTANT: Save the generated root password before reboot:${NC} ${YELLOW}${ROOT_PASS}${NC}"
fi

echo -ne "\nRebooting in "
for i in {10..1}; do echo -n "$i... "; sleep 1; done
echo -e "\n${RED}${BOLD}Rebooting now!${NC}"
sync && sleep 2

if [ "$OS_TYPE" = "debian" ]; then
    reboot -f
else
    pkill -TERM sshd 2>/dev/null || true
    sleep 1
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
    echo b > /proc/sysrq-trigger 2>/dev/null || true
    reboot -f -n 2>/dev/null || true
    systemctl reboot --force --force 2>/dev/null || true
    python3 -c "import ctypes; ctypes.CDLL('libc.so.6').reboot(0x1234567)" 2>/dev/null || true
fi
