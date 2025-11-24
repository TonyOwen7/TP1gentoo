#!/bin/bash
# Automatic, safe & idempotent GRUB install into MBR for Gentoo

set -euo pipefail

DISK="/dev/sda"
MNT="/mnt/gentoo"

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

msg() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[X]${NC} $1"; exit 1; }

###############################################
# 1) MOUNT TARGET SYSTEM
###############################################
msg "Mounting root..."

mkdir -p "$MNT"
mount | grep -q "$MNT " || mount "${DISK}3" "$MNT"

mkdir -p "$MNT/boot"
mount | grep -q "$MNT/boot " || mount "${DISK}1" "$MNT/boot"

mkdir -p "$MNT/home"
mount | grep -q "$MNT/home " || mount "${DISK}4" "$MNT/home"

swapon "${DISK}2" 2>/dev/null || true

msg "Binding proc/sys/dev/run..."

mount | grep -q "$MNT/proc " || mount -t proc /proc "$MNT/proc"
mount | grep -q "$MNT/sys "  || mount --rbind /sys "$MNT/sys"
mount | grep -q "$MNT/dev "  || mount --rbind /dev "$MNT/dev"
mount | grep -q "$MNT/run "  || mount --rbind /run "$MNT/run"

cp -L /etc/resolv.conf "$MNT/etc/" || true

ok "Mount OK"


###############################################
# 2) CHECK KERNEL EXISTENCE
###############################################
msg "Checking kernel in /boot..."

if ls "$MNT/boot/vmlinuz"* >/dev/null 2>&1; then
    ok "Kernel found"
else
    err "NO kernel found — install kernel BEFORE grub"
fi


###############################################
# 3) INSTALL GRUB IF NEEDED LOCALLY
###############################################
msg "Checking if GRUB is installed in system..."

if chroot "$MNT" grub-install --version >/dev/null 2>&1; then
    ok "GRUB already installed locally"
else
    msg "Installing GRUB package..."
    chroot "$MNT" emerge --noreplace sys-boot/grub || err "failed to emerge grub"
    ok "GRUB installed"
fi


###############################################
# 4) INSTALL TO MBR ONLY IF NOT PRESENT
###############################################
msg "Checking MBR signature..."

if dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    ok "MBR already has GRUB — skipping"
else
    msg "Installing GRUB into MBR..."
    chroot "$MNT" grub-install "$DISK" || err "grub-install failed"
    ok "GRUB installed into MBR"
fi


###############################################
# 5) GENERATE grub.cfg IF NEEDED
###############################################
msg "Checking grub.cfg..."

if [ -f "$MNT/boot/grub/grub.cfg" ]; then
    ok "grub.cfg exists"
else
    msg "Generating new grub.cfg..."
    chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
    ok "grub.cfg generated"
fi


###############################################
# DONE
###############################################
ok "GRUB is ready. You can now reboot safely."
