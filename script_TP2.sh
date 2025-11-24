#!/usr/bin/env bash
# emergency_grub_fix.sh
# Correction d'urgence GRUB MBR

set -euo pipefail

DISK="/dev/sda"
MNT="/mnt/gentoo"

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
echo_red() { echo -e "${RED}$1${NC}"; }
echo_green() { echo -e "${GREEN}$1${NC}"; }

[ "$(id -u)" -eq 0 ] || { echo_red "Run as root!"; exit 1; }

echo "========================================"
echo " CORRECTION URGENCE MBR GRUB"
echo "========================================"

# Montage minimal
mount /dev/sda3 $MNT || exit 1
mount /dev/sda1 $MNT/boot || exit 1

for fs in dev proc sys; do
    mount --rbind /$fs $MNT/$fs && mount --make-rslave $MNT/$fs
done

# Correction extrême
chroot $MNT /bin/bash << 'EOF'
echo "Installation GRUB en mode urgence..."

# Méthode directe
grub-install --force /dev/sda || \
grub-install --target=i386-pc --force /dev/sda || \
{
    echo "Méthode d'urgence: écriture directe MBR"
    if [ -f /usr/lib/grub/i386-pc/boot.img ]; then
        dd if=/usr/lib/grub/i386-pc/boot.img of=/dev/sda bs=446 count=1
        echo "MBR écrit directement"
    fi
}

# Créer grub.cfg minimal
cat > /boot/grub/grub.cfg << 'GRUB_CFG'
set timeout=3
menuentry "Gentoo" {
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro
    boot
}
GRUB_CFG

echo "Vérification..."
dd if=/dev/sda bs=512 count=1 | strings | grep -q "GRUB" && echo "SUCCÈS" || echo "ÉCHEC"
EOF

umount -R $MNT
echo_green "Correction terminée. Redémarrez."