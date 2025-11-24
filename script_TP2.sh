#!/usr/bin/env bash
# safe_grub_gentoo.sh
# Script sûr pour chrooter et installer GRUB (BIOS/UEFI) sans créer de doublons de montage
# Run as root from LiveCD

set -euo pipefail

# === Configuration ===
DISK="/dev/sda"
PART_ROOT="/dev/sda3"
PART_BOOT="/dev/sda1"
PART_HOME="/dev/sda4"
PART_SWAP="/dev/sda2"
MNT="/mnt/gentoo"
BOOT_DIR="/boot"
EFI_DIR="/boot/efi"
GRUB_ID="Gentoo"

# === Colors ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Root check ===
[ "$(id -u)" -eq 0 ] || err "This script must be run as root."

info "Disk: $DISK"
info "Root partition: $PART_ROOT"
info "Boot partition: $PART_BOOT"
info "Home partition: $PART_HOME"
info "Mount point: $MNT"

# === 1️⃣ Nettoyer les montages fantômes ===
umount -l "$MNT/boot" 2>/dev/null || true
umount -l "$MNT/home" 2>/dev/null || true
umount -l "$MNT" 2>/dev/null || true

# === 2️⃣ Monter les partitions correctement ===
mount "$PART_ROOT" "$MNT" || err "Failed to mount root"
ok "Mounted root: $PART_ROOT -> $MNT"

mkdir -p "$MNT$BOOT_DIR"
mount "$PART_BOOT" "$MNT$BOOT_DIR" || err "Failed to mount boot"
ok "Mounted boot: $PART_BOOT -> $MNT$BOOT_DIR"

if [ -b "$PART_HOME" ]; then
    mkdir -p "$MNT/home"
    mount "$PART_HOME" "$MNT/home" || warn "Home mount failed"
fi

if [ -b "$PART_SWAP" ]; then
    swapon "$PART_SWAP" 2>/dev/null || warn "Swap enable failed"
fi

# === 3️⃣ Bind mounts pour chroot ===
for fs in dev sys proc run; do
    mountpoint -q "$MNT/$fs" || mount --rbind "/$fs" "$MNT/$fs"
    mount --make-rslave "$MNT/$fs" 2>/dev/null || true
done

# Copie resolv.conf
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" || warn "No resolv.conf"

# === 4️⃣ Entrée dans chroot pour GRUB ===
info "Entering chroot to install GRUB..."
chroot "$MNT" /bin/bash -eux <<'CHROOT_EOF'
set -euo pipefail

BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${BLUE}[CHROOT INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[CHROOT OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[CHROOT WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[CHROOT ERROR]${NC} %s\n" "$*"; exit 1; }

export PS1="(chroot) \$ "

# Installer GRUB si nécessaire
if ! command -v grub-install >/dev/null 2>&1; then
    [ -x /usr/bin/emerge ] && emerge --noreplace sys-boot/grub || err "grub missing and cannot install"
else
    ok "GRUB binary present"
fi

# Détecter BIOS ou UEFI
INSTALL_MODE="bios"
if [ -d /boot/efi ] && mountpoint -q /boot/efi; then
    INSTALL_MODE="uefi"
elif [ -d /sys/firmware/efi ]; then
    INSTALL_MODE="uefi"
fi
info "GRUB install mode: $INSTALL_MODE"

# Installer GRUB
if [ "$INSTALL_MODE" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || warn "UEFI grub-install failed"
else
    grub-install --target=i386-pc /dev/sda || err "BIOS grub-install failed"
fi
ok "grub-install done"

# Générer grub.cfg
if [ -f /boot/grub/grub.cfg ]; then
    cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
fi
grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg generated" || warn "grub-mkconfig failed"
CHROOT_EOF

# === 5️⃣ Post check ===
[ -f "$MNT$BOOT_DIR/grub/grub.cfg" ] && ok "Found grub.cfg" || warn "No grub.cfg found"

info "Unmount & reboot when ready:"
echo "umount -R $MNT"
echo "swapoff $PART_SWAP 2>/dev/null || true"
echo "reboot"
