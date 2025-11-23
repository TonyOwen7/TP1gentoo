#!/bin/bash
# Script de diagnostic après reboot - Rien n'est monté

set -euo pipefail

echo "================================================================"
echo "     Diagnostic boot Gentoo - Rien n'est monté"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION 1 : Où sommes-nous ?
# ============================================================================
echo "[DIAG 1] Vérification de l'environnement actuel"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] Hostname actuel:"
hostname

echo ""
echo "[INFO] Système de fichiers racine:"
df -h / | grep -v Filesystem

echo ""
echo "[INFO] Contenu de /boot (si accessible):"
ls -la /boot/ 2>/dev/null || echo "  /boot vide ou non monté"

echo ""
echo "[INFO] Noyau actuel:"
uname -a

echo ""
if [ -f "/etc/gentoo-release" ]; then
    echo "[OK] ✓ Vous êtes sur Gentoo"
    cat /etc/gentoo-release
else
    echo "[WARNING] ✗ Vous êtes probablement sur le LiveCD"
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  PROBLÈME: Le système n'a PAS booté sur Gentoo installé   ║"
    echo "║  Vous êtes toujours sur le LiveCD !                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
fi

# ============================================================================
# VÉRIFICATION 2 : État des partitions
# ============================================================================
echo ""
echo "[DIAG 2] État des partitions du disque"
echo "════════════════════════════════════════════════════════════"
lsblk /dev/sda

echo ""
echo "[INFO] Labels des partitions:"
blkid /dev/sda* 2>/dev/null || true

echo ""
echo "[INFO] Fichiers dans /dev/sda1 (boot):"
mkdir -p /tmp/check_boot
mount /dev/sda1 /tmp/check_boot 2>/dev/null || true
ls -lh /tmp/check_boot/
echo ""
echo "[INFO] Noyaux présents:"
ls -lh /tmp/check_boot/vmlinuz-* 2>/dev/null || echo "  ✗ Aucun noyau trouvé"
echo ""
echo "[INFO] GRUB présent:"
ls -la /tmp/check_boot/grub/ 2>/dev/null | head -10 || echo "  ✗ Pas de GRUB"

# ============================================================================
# VÉRIFICATION 3 : Configuration GRUB
# ============================================================================
echo ""
echo "[DIAG 3] Vérification de la configuration GRUB"
echo "════════════════════════════════════════════════════════════"

if [ -f "/tmp/check_boot/grub/grub.cfg" ]; then
    echo "[OK] ✓ grub.cfg existe"
    echo ""
    echo "[INFO] Entrées de menu dans grub.cfg:"
    grep "^menuentry" /tmp/check_boot/grub/grub.cfg | head -5
    echo ""
    echo "[INFO] Lignes 'linux' (noyau à charger):"
    grep -E "^[[:space:]]+linux" /tmp/check_boot/grub/grub.cfg | head -5
    echo ""
    echo "[INFO] Paramètre root:"
    grep -E "^[[:space:]]+linux" /tmp/check_boot/grub/grub.cfg | grep -o "root=[^ ]*" | head -3
else
    echo "[ERROR] ✗ grub.cfg N'EXISTE PAS"
    echo "  Ceci explique pourquoi le système ne boot pas !"
fi

# ============================================================================
# VÉRIFICATION 4 : MBR et GRUB
# ============================================================================
echo ""
echo "[DIAG 4] Vérification du MBR et GRUB"
echo "════════════════════════════════════════════════════════════"

echo "[INFO] Recherche de GRUB dans le MBR:"
dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -i grub || echo "  ✗ GRUB non trouvé dans le MBR"

# ============================================================================
# DIAGNOSTIC FINAL
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "DIAGNOSTIC FINAL"
echo "════════════════════════════════════════════════════════════"
echo ""

KERNEL_EXISTS=$(ls /tmp/check_boot/vmlinuz-* 2>/dev/null | wc -l)
GRUB_CFG_EXISTS=$([ -f "/tmp/check_boot/grub/grub.cfg" ] && echo "1" || echo "0")
GRUB_IN_MBR=$(dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -qi grub && echo "1" || echo "0")

echo "Vérifications:"
echo "  • Noyau dans /boot: $([ "$KERNEL_EXISTS" -gt 0 ] && echo '✓ OUI' || echo '✗ NON')"
echo "  • grub.cfg existe: $([ "$GRUB_CFG_EXISTS" = "1" ] && echo '✓ OUI' || echo '✗ NON')"
echo "  • GRUB dans MBR: $([ "$GRUB_IN_MBR" = "1" ] && echo '✓ OUI' || echo '✗ NON')"
echo ""

# ============================================================================
# SOLUTIONS PROPOSÉES
# ============================================================================
echo "════════════════════════════════════════════════════════════"
echo "SOLUTIONS POSSIBLES"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ "$KERNEL_EXISTS" = "0" ]; then
    echo "❌ PROBLÈME 1: Aucun noyau dans /boot"
    echo "   CAUSE: La compilation ou l'installation du noyau a échoué"
    echo "   SOLUTION: Relancer le TP2 depuis l'exercice 2.4"
    echo ""
fi

if [ "$GRUB_CFG_EXISTS" = "0" ]; then
    echo "❌ PROBLÈME 2: grub.cfg manquant"
    echo "   CAUSE: grub-mkconfig n'a pas été exécuté ou a échoué"
    echo "   SOLUTION:"
    echo "     mount /dev/sda3 /mnt/gentoo"
    echo "     mount /dev/sda1 /mnt/gentoo/boot"
    echo "     # Monter sys/proc/dev"
    echo "     chroot /mnt/gentoo"
    echo "     grub-mkconfig -o /boot/grub/grub.cfg"
    echo ""
fi

if [ "$GRUB_IN_MBR" = "0" ]; then
    echo "❌ PROBLÈME 3: GRUB non installé dans le MBR"
    echo "   CAUSE: grub-install n'a pas été exécuté ou a échoué"
    echo "   SOLUTION:"
    echo "     mount /dev/sda3 /mnt/gentoo"
    echo "     mount /dev/sda1 /mnt/gentoo/boot"
    echo "     # Monter sys/proc/dev"
    echo "     chroot /mnt/gentoo"
    echo "     grub-install /dev/sda"
    echo "     grub-mkconfig -o /boot/grub/grub.cfg"
    echo ""
fi

# ============================================================================
# SCRIPT DE CORRECTION AUTOMATIQUE
# ============================================================================
echo "════════════════════════════════════════════════════════════"
echo "CORRECTION AUTOMATIQUE"
echo "════════════════════════════════════════════════════════════"
echo ""

read -p "Voulez-vous tenter une correction automatique ? (oui/non) : " CONFIRM

if [ "$CONFIRM" = "oui" ]; then
    echo ""
    echo "[FIX] Début de la correction..."
    echo ""
    
    # Montage
    echo "[1/6] Montage des partitions..."
    MOUNT_POINT="/mnt/gentoo"
    mkdir -p "${MOUNT_POINT}"
    
    umount -R "${MOUNT_POINT}" 2>/dev/null || true
    
    mount /dev/sda3 "${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"/{boot,home,proc,sys,dev,run}
    mount /dev/sda1 "${MOUNT_POINT}/boot"
    mount /dev/sda4 "${MOUNT_POINT}/home" 2>/dev/null || true
    swapon /dev/sda2 2>/dev/null || true
    
    mount -t proc /proc "${MOUNT_POINT}/proc"
    mount --rbind /sys "${MOUNT_POINT}/sys"
    mount --make-rslave "${MOUNT_POINT}/sys"
    mount --rbind /dev "${MOUNT_POINT}/dev"
    mount --make-rslave "${MOUNT_POINT}/dev"
    mount --bind /run "${MOUNT_POINT}/run"
    
    cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"
    
    echo "[OK] Partitions montées"
    echo ""
    
    # Vérifications dans le chroot
    echo "[2/6] Vérification du noyau..."
    
    chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_FIX'
#!/bin/bash
source /etc/profile

echo "[INFO] Noyaux présents dans /boot:"
ls -lh /boot/vmlinuz-* 2>/dev/null || echo "  ✗ Aucun noyau"

if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
    echo ""
    echo "[ERROR] Aucun noyau trouvé !"
    echo "[INFO] Vous devez relancer la compilation:"
    echo "  cd /usr/src/linux"
    echo "  make"
    echo "  make modules_install"
    echo "  make install"
    exit 1
fi

echo ""
echo "[3/6] Installation/Réinstallation de GRUB..."
grub-install /dev/sda

echo ""
echo "[4/6] Génération de grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg

echo ""
echo "[5/6] Vérification de grub.cfg..."
if [ -f /boot/grub/grub.cfg ]; then
    echo "[OK] grub.cfg créé"
    echo ""
    echo "[INFO] Entrées de menu:"
    grep "^menuentry" /boot/grub/grub.cfg | head -3
else
    echo "[ERROR] grub.cfg non créé"
    exit 1
fi

echo ""
echo "[6/6] Vérifications finales..."
echo "  ✓ Noyau: $(ls /boot/vmlinuz-* | head -1)"
echo "  ✓ GRUB: Installé"
echo "  ✓ grub.cfg: $(grep -c '^menuentry' /boot/grub/grub.cfg) entrées"
echo ""
echo "[SUCCESS] Correction terminée"

CHROOT_FIX
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "[SUCCESS] ✅ CORRECTION TERMINÉE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "🚀 MAINTENANT:"
    echo "  1. cd /"
    echo "  2. umount -R /mnt/gentoo"
    echo "  3. reboot"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "  • Retirez le LiveCD de VirtualBox AVANT de redémarrer"
    echo "  • Paramètres VM > Stockage > Retirer le ISO"
    echo ""
    
else
    echo ""
    echo "[INFO] Correction annulée"
    echo ""
    echo "📋 POUR CORRECTION MANUELLE:"
    echo "  1. mount /dev/sda3 /mnt/gentoo"
    echo "  2. mount /dev/sda1 /mnt/gentoo/boot"
    echo "  3. mount -t proc /proc /mnt/gentoo/proc"
    echo "  4. mount --rbind /sys /mnt/gentoo/sys"
    echo "  5. mount --rbind /dev /mnt/gentoo/dev"
    echo "  6. chroot /mnt/gentoo /bin/bash"
    echo "  7. source /etc/profile"
    echo "  8. grub-install /dev/sda"
    echo "  9. grub-mkconfig -o /boot/grub/grub.cfg"
    echo "  10. exit"
    echo "  11. reboot"
    echo ""
fi

# Nettoyage
umount /tmp/check_boot 2>/dev/null || true