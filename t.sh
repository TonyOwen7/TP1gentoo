#!/bin/bash
# Automatic GRUB install into MBR IF needed only
# Idempotent, safe, detects what is already present

set -euo pipefail

DISK="/dev/sda"
MNT="/mnt/gentoo"

########################################
# FUNCTIONS
########################################
msg() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1"; }
ok()  { printf "\033[1;32m[OK]\033[0m %s\n" "$1"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$1"; }
err() { printf "\033[1;31m[X]\033[0m %s\n" "$1"; exit 1; }

########################################
# 1) MOUNT
########################################
msg "Mounting target system..."

umount -R "$MNT" 2>/dev/null || true

mount "${DISK}3" "$MNT" || err "cannot mount root"
mkdir -p "$MNT/boot"
mount "${DISK}1" "$MNT/boot" 2>/dev/null || warn "boot already mounted?"

mount -t proc /proc        "$MNT/proc"
mount --rbind /sys         "$MNT/sys"
mount --rbind /dev         "$MNT/dev"

cp -L /etc/resolv.conf "$MNT/etc/"

########################################
# 2) checks
########################################
msg "Checking kernel..."
if ls "$MNT/boot/vmlinuz"* >/dev/null 2>&1; then
    ok "kernel found"
else
    err "no kernel installed"
fi

msg "Checking GRUB presence..."
if chroot "$MNT" grub-install --version >/dev/null 2>&1; then
    ok "grub binary present"
else
    msg "installing grub..."
    chroot "$MNT" emerge --ask=n sys-boot/grub || err "failed grub install"
fi

########################################
# 3) install into MBR ONLY if not present
########################################
msg "Checking if MBR contains GRUB signature..."
if dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    ok "GRUB already in MBR — skipping"
else
    msg "Installing GRUB into disk MBR..."
    chroot "$MNT" grub-install "$DISK" || err "grub-install failed"
    ok "GRUB installed into MBR"
fi

########################################
# 4) mkconfig if needed
########################################
msg "Checking grub.cfg..."
if [ -f "$MNT/boot/grub/grub.cfg" ]; then
    ok "grub.cfg exists"
else
    msg "Generating new grub.cfg..."
    chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
    ok "generated grub.cfg"
fi

########################################
# done
########################################
ok "All done. Unmount & reboot when ready."
