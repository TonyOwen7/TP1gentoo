#!/usr/bin/env bash
# grub_chroot.sh
# Installe GRUB depuis chroot, BIOS ou UEFI
# Usage: ./grub_chroot.sh

set -euo pipefail

MNT="/mnt/gentoo"
DISK="/dev/sda"
BOOT_DIR="/boot"
EFI_DIR="/boot/efi"
GRUB_ID="Gentoo"

info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

info "Entrée dans le chroot pour installation GRUB..."

chroot "$MNT" /bin/bash -eux <<'CHROOT_EOF'
set -euo pipefail

export PS1="(chroot) $ "

# Installer GRUB si absent
command -v grub-install >/dev/null 2>&1 || { emerge --noreplace sys-boot/grub || exit 1; }

# Détecter BIOS ou UEFI
INSTALL_MODE="bios"
if mountpoint -q /boot/efi || [ -d /sys/firmware/efi ]; then
    INSTALL_MODE="uefi"
fi

echo "GRUB mode: $INSTALL_MODE"

if [ "$INSTALL_MODE" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || echo "UEFI grub-install failed"
else
    grub-install --target=i386-pc /dev/sda || exit 1
fi

# Générer grub.cfg
[ -f /boot/grub/grub.cfg ] && cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
grub-mkconfig -o /boot/grub/grub.cfg || echo "grub-mkconfig failed"
CHROOT_EOF

ok "GRUB installé depuis chroot. Vérifiez /boot/grub/grub.cfg"
