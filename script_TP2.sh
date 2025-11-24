#!/usr/bin/env bash
# safe_grub_install.sh
# Installe GRUB sur Gentoo depuis un LiveCD
# BIOS (i386-pc) ou UEFI (x86_64-efi) selon partition boot
# Usage: run as root
# chmod +x safe_grub_install.sh
# ./safe_grub_install.sh

set -euo pipefail

# === Configuration ===
DISK="/dev/sda"             # disque entier pour BIOS
PART_BOOT="/dev/sda1"       # partition boot (EFI ou /boot)
PART_ROOT="/dev/sda3"       # root
PART_HOME="/dev/sda4"       # home (optionnel)
PART_SWAP="/dev/sda2"       # swap (optionnel)
MNT="/mnt/gentoo"           # point de montage root
BOOT_DIR="/boot"            # relatif au chroot
EFI_DIR="/boot/efi"         # pour UEFI
GRUB_ID="Gentoo"

# === Fonctions couleurs ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Root check ===
[ "$(id -u)" -eq 0 ] || err "Run as root!"

# === Vérification partitions ===
for p in "$PART_ROOT" "$PART_BOOT"; do
    [ -b "$p" ] || err "Device $p not found"
done

info "Root: $PART_ROOT, Boot: $PART_BOOT, Disk: $DISK"

# === Montage safe ===
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$PART_ROOT" "$MNT" || err "Failed mount root"
ok "Root mounted"

mkdir -p "$MNT$BOOT_DIR"
mountpoint -q "$MNT$BOOT_DIR" || mount "$PART_BOOT" "$MNT$BOOT_DIR" || warn "Boot mount failed"
ok "Boot mounted"

[ -b "$PART_HOME" ] && mkdir -p "$MNT/home" && mountpoint -q "$MNT/home" || mount "$PART_HOME" "$MNT/home" 2>/dev/null || true
[ -b "$PART_SWAP" ] && swapon "$PART_SWAP" 2>/dev/null || true

# === Bind mounts ===
for fs in dev sys proc run; do
    mountpoint -q "$MNT/$fs" || mount --rbind "/$fs" "$MNT/$fs"
    mount --make-rslave "$MNT/$fs"
done

# Copy resolv.conf
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" || warn "No /etc/resolv.conf"

# === Chroot installation ===
info "Entering chroot..."

chroot "$MNT" /bin/bash -eux <<'CHROOT_EOF'
set -euo pipefail
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[CHROOT INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[CHROOT OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[CHROOT WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[CHROOT ERROR]${NC} %s\n" "$*"; exit 1; }

# PS1 pour bash
export PS1="(chroot) \$ "

# Installer GRUB si absent
command -v grub-install >/dev/null 2>&1 || { info "Installing GRUB"; emerge --noreplace sys-boot/grub || err "Cannot install grub"; }

# Détecter BIOS ou UEFI
INSTALL_MODE="bios"
if mountpoint -q /boot/efi || [ -d /sys/firmware/efi ]; then
    INSTALL_MODE="uefi"
fi
info "GRUB mode: $INSTALL_MODE"

# Installer GRUB correctement
if [ "$INSTALL_MODE" = "uefi" ]; then
    info "Installing UEFI GRUB..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || warn "UEFI grub-install failed"
else
    info "Installing BIOS GRUB on /dev/sda..."
    grub-install --target=i386-pc /dev/sda || err "BIOS grub-install failed"
fi

# Générer grub.cfg
[ -f /boot/grub/grub.cfg ] && cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg generated"

CHROOT_EOF

ok "Returned from chroot"
ok "Script finished. Verify /boot/grub/grub.cfg and reboot when ready:"
cat <<EOF
umount -R $MNT
swapoff $PART_SWAP 2>/dev/null || true
reboot
EOF
