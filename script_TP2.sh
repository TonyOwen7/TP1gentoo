#!/usr/bin/env bash
# manual_boot_helper.sh
# Aide au boot manuel immédiat

set -e

echo "🎯 BOOT MANUEL IMMÉDIAT"

# Monter pour vérifier le noyau
mount /dev/sda3 /mnt/gentoo
mount /dev/sda1 /mnt/gentoo/boot

echo "=== NOYAUX DISPONIBLES ==="
find /mnt/gentoo/boot -name "vmlinuz*" 2>/dev/null || echo "❌ Aucun noyau!"

echo ""
echo "=== INSTRUCTIONS BOOT MANUEL ==="
echo "1. Redémarrez: reboot"
echo "2. Au démarrage, appuyez sur 'c' pour GRUB"
echo "3. Commandes EXACTES:"
echo "   set root=(hd0,msdos1)"
echo "   linux /vmlinuz-$(ls /mnt/gentoo/boot/vmlinuz* 2>/dev/null | head -1 | sed 's|.*vmlinuz-||') root=/dev/sda3 ro"
echo "   boot"
echo ""
echo "4. Si aucun noyau, utilisez:"
echo "   linux /vmlinuz root=/dev/sda3 ro"
echo "   boot"

umount /mnt/gentoo/boot
umount /mnt/gentoo

echo ""
echo "⚠️  CECI EST UNE SOLUTION TEMPORAIRE!"
echo "   Le système bootera mais GRUB ne sera pas permanent."