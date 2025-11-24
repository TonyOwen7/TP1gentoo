#!/usr/bin/env bash
# ultra_minimal_grub_fix.sh
# Solution ultra-minimaliste pour GRUB

set -e

DISK="/dev/sda"
MNT="/mnt/gentoo"

echo "=== INSTALLATION GRUB ULTRA-MINIMALISTE ==="

# Montage basique
mount /dev/sda3 $MNT
mount /dev/sda1 $MNT/boot

# Entrée chroot simple
chroot $MNT << 'EOF'
echo "Installation GRUB ultra-minimaliste..."

# Vérifier les outils basiques
which grub-install >/dev/null || {
    echo "GRUB non trouvé, installation..."
    emerge --noreplace sys-boot/grub || exit 1
}

# Installation directe sans vérifications
echo "Installation GRUB directe..."
grub-install --target=i386-pc --force --no-nvram /dev/sda

# Création grub.cfg ultra-simple
echo "Création grub.cfg..."
cat > /boot/grub/grub.cfg << 'GRUB'
set timeout=3
menuentry "Gentoo" {
    linux /vmlinuz root=/dev/sda3 ro
    boot
}
GRUB

echo "Installation terminée"
EOF

umount $MNT/boot
umount $MNT
echo "=== TERMINÉ ==="