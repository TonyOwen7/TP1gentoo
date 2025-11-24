#!/usr/bin/env bash
# install_grub_gentoo.sh
# Safe, idempotent GRUB installer for Gentoo (BIOS & optional UEFI)
# Run as root from LiveCD
# Usage:
#   chmod +x install_grub_gentoo.sh
#   ./install_grub_gentoo.sh

set -euo pipefail

# === Configuration ===
DISK="${DISK:-/dev/sda}"        # physical disk for BIOS GRUB install
PART_BOOT="${PART_BOOT:-/dev/sda1}"
PART_SWAP="${PART_SWAP:-/dev/sda2}"
PART_ROOT="${PART_ROOT:-/dev/sda3}"
PART_HOME="${PART_HOME:-/dev/sda4}"
MNT="${MNT:-/mnt/gentoo}"
BOOT_DIR="/boot"                 # relative to chroot
EFI_DIR="/boot/efi"              # for UEFI
GRUB_ID="Gentoo"                 # EFI bootloader ID

# === Colors ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Root check ===
[ "$(id -u)" -eq 0 ] || err "This script must be run as root."

# === Check devices exist ===
for p in "$PART_ROOT" "$PART_BOOT"; do
    [ -b "$p" ] || err "Block device $p not found. Check your PART_* variables."
done

info "Disk: $DISK"
info "Root partition: $PART_ROOT"
info "Boot partition: $PART_BOOT"
info "Mount point: $MNT"

# === Mount partitions ===
mkdir -p "$MNT"
mount "$PART_ROOT" "$MNT" 2>/dev/null || ok "$PART_ROOT already mounted"
mkdir -p "${MNT}${BOOT_DIR}"
mount "$PART_BOOT" "${MNT}${BOOT_DIR}" 2>/dev/null || ok "$PART_BOOT already mounted"

# Optional mounts
[ -b "$PART_HOME" ] && mkdir -p "${MNT}/home" && mount "$PART_HOME" "${MNT}/home" 2>/dev/null || true
[ -b "$PART_SWAP" ] && swapon "$PART_SWAP" 2>/dev/null || true

# === Bind mounts for chroot ===
for fs in dev sys proc run; do
    mount --rbind "/$fs" "$MNT/$fs" 2>/dev/null || true
    mount --make-rslave "$MNT/$fs" 2>/dev/null || true
done

# Copy network config
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" || warn "No /etc/resolv.conf"

# === Kernel check ===
if ls "$MNT${BOOT_DIR}/vmlinuz"* >/dev/null 2>&1; then
    ok "Kernel found in $BOOT_DIR"
else
    warn "No kernel found. grub-install may fail until kernel is installed."
fi

# === Chroot and install GRUB ===
info "Entering chroot to install GRUB..."

chroot "$MNT" /bin/bash -eux <<'CHROOT_EOF'
set -euo pipefail

# Colored output in chroot
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[CHROOT INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[CHROOT OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[CHROOT WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[CHROOT ERROR]${NC} %s\n" "$*"; exit 1; }

export PS1="(chroot) ${PS1:-\$ }"

# === Start udev for BIOS GRUB detection ===
if command -v /etc/init.d/udev >/dev/null 2>&1; then
    /etc/init.d/udev start || warn "udev start failed"
fi

# Install grub if missing
if ! command -v grub-install >/dev/null 2>&1; then
    info "Installing GRUB package..."
    [ -x /usr/bin/emerge ] && emerge --noreplace sys-boot/grub || err "grub missing and cannot install"
else
    ok "grub binary present"
fi

# Detect BIOS vs UEFI
INSTALL_MODE="bios"
if [ -d /boot/efi ] && mountpoint -q /boot/efi; then
    INSTALL_MODE="uefi"
elif [ -d /sys/firmware/efi ]; then
    INSTALL_MODE="uefi"
fi
info "GRUB install mode: $INSTALL_MODE"

# === Install GRUB ===
if [ "$INSTALL_MODE" = "uefi" ]; then
    info "Installing GRUB for UEFI..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || warn "UEFI grub-install failed"
else
    info "Installing GRUB for BIOS..."
    grub-install --target=i386-pc /dev/sda || err "BIOS grub-install failed"
fi
ok "grub-install done"

# === Generate grub.cfg ===
if [ -f /boot/grub/grub.cfg ]; then
    info "Backing up existing grub.cfg..."
    cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
fi
grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg generated" || warn "grub-mkconfig failed"
CHROOT_EOF

info "Returned from chroot."

# === Post checks ===
[ -f "${MNT}${BOOT_DIR}/grub/grub.cfg" ] && ok "Found grub.cfg" || warn "No grub.cfg found"

if command -v strings >/dev/null 2>&1; then
    dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && ok "GRUB signature in MBR" || warn "No GRUB signature in MBR"
else
    warn "strings command not available, skipping MBR check"
fi

echo
ok "GRUB installation script finished."
echo "Unmount & reboot when ready:"
cat <<EOF
umount -R $MNT
swapoff $PART_SWAP 2>/dev/null || true
reboot
EOF
