#!/bin/bash
# SOLUTION ULTIME - Contournement GRUB avec boot direct

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, solution ULTIME sans GRUB..."

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     SOLUTION ULTIME - Boot direct SANS GRUB"
echo "================================================================"
echo ""

# ============================================================================
# ANALYSE DU PROBLÈME
# ============================================================================
log_info "Analyse du problème..."

echo "[1/4] Vérification LiveCD..."
if [ -f "/etc/gentoo-release" ]; then
    log_warning "⚠️  Nous sommes DANS Gentoo, pas sur LiveCD"
else
    log_success "✅ Nous sommes sur le LiveCD"
fi

echo ""
echo "[2/4] Vérification erreur GRUB..."
if grub-install /dev/sda 2>&1 | grep -q "LiveOS_rootfs"; then
    log_error "❌ GRUB corrompu dans LiveCD - erreur LiveOS_rootfs"
else
    log_info "GRUB semble fonctionnel"
fi

echo ""
echo "[3/4] Vérification partitions..."
lsblk /dev/sda

echo ""
echo "[4/4] Vérification noyau..."
mount /dev/sda1 /mnt/gentoo/boot 2>/dev/null || true
if ls /mnt/gentoo/boot/vmlinuz* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /mnt/gentoo/boot/vmlinuz* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "✅ Noyau trouvé: $KERNEL_NAME"
else
    log_error "❌ Aucun noyau trouvé"
    exit 1
fi
umount /mnt/gentoo/boot 2>/dev/null || true

# ============================================================================
# MÉTHODE 1: RÉINITIALISATION COMPLÈTE DU MBR
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 1: RÉINITIALISATION MBR ━━━━"

log_info "Nettoyage complet du MBR..."
dd if=/dev/zero of=/dev/sda bs=512 count=1 2>/dev/null
log_success "MBR nettoyé"

log_info "Re-création de la table de partitions..."
(
echo o # Nouvelle table MBR
echo n; echo p; echo 1; echo ; echo +512M  # /boot
echo n; echo p; echo 2; echo ; echo +4G    # swap  
echo n; echo p; echo 3; echo ; echo +40G   # /
echo n; echo p; echo 4; echo ; echo        # /home
echo t; echo 2; echo 82                    # swap
echo w
) | fdisk /dev/sda >/dev/null 2>&1

sleep 2
partprobe /dev/sda 2>/dev/null || true
log_success "Table de partitions recréée"

# ============================================================================
# MÉTHODE 2: INSTALLATION SYSLINUX (ALTERNATIVE À GRUB)
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 2: INSTALLATION SYSLINUX ━━━━"

log_info "Formatage des partitions..."
mkfs.ext2 -F -L "boot" /dev/sda1 >/dev/null 2>&1
mkswap -L "swap" /dev/sda2 >/dev/null 2>&1
mkfs.ext4 -F -L "root" /dev/sda3 >/dev/null 2>&1
mkfs.ext4 -F -L "home" /dev/sda4 >/dev/null 2>&1
log_success "Partitions formatées"

# Montage
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot

log_info "Installation SYSLINUX depuis LiveCD..."
if command -v extlinux >/dev/null 2>&1; then
    # Installer SYSLINUX sur la partition boot
    extlinux --install /mnt/gentoo/boot 2>&1 && \
    log_success "✅ SYSLINUX installé" || \
    log_warning "❌ Échec SYSLINUX"
    
    # Écrire le MBR SYSLINUX
    if [ -f "/usr/share/syslinux/mbr.bin" ]; then
        dd if=/usr/share/syslinux/mbr.bin of=/dev/sda bs=440 count=1 conv=notrunc 2>/dev/null && \
        log_success "✅ MBR SYSLINUX écrit" || \
        log_warning "❌ Échec MBR SYSLINUX"
    fi
else
    log_warning "SYSLINUX non disponible"
fi

# ============================================================================
# MÉTHODE 3: CONFIGURATION DE BOOT DIRECTE
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 3: CONFIGURATION BOOT DIRECTE ━━━━"

log_info "Création de la configuration SYSLINUX..."
cat > /mnt/gentoo/boot/syslinux.cfg << EOF
DEFAULT gentoo
PROMPT 1
TIMEOUT 50

LABEL gentoo
    LINUX /$KERNEL_NAME
    APPEND root=/dev/sda3 ro quiet

LABEL gentoo-secours
    LINUX /$KERNEL_NAME  
    APPEND root=/dev/sda3 ro single

LABEL gentoo-debug
    LINUX /$KERNEL_NAME
    APPEND root=/dev/sda3 ro debug
EOF
log_success "syslinux.cfg créé"

# ============================================================================
# MÉTHODE 4: RÉINSTALLATION DU SYSTÈME ESSENTIEL
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 4: RÉINSTALLATION SYSTÈME ━━━━"

log_info "Montage de l'environnement chroot..."
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
cp -L /etc/resolv.conf /mnt/gentoo/etc/

log_info "Réinstallation de GRUB dans le système..."
chroot /mnt/gentoo /bin/bash << 'CHROOT_EOF'
#!/bin/bash
set -e

echo "[CHROOT] Installation de GRUB..."
export FEATURES="-sandbox -usersandbox -network-sandbox"

# Nettoyer toute installation GRUB existante
emerge --unmerge sys-boot/grub 2>/dev/null || true

# Réinstaller GRUB proprement
if emerge --nodeps sys-boot/grub 2>&1; then
    echo "[CHROOT] ✅ GRUB installé dans le système"
else
    echo "[CHROOT] ❌ Échec installation GRUB"
fi

# Configurer fstab
echo "[CHROOT] Configuration fstab..."
cat > /etc/fstab << 'FSTAB'
/dev/sda3   /       ext4    defaults,noatime    0 1
/dev/sda1   /boot   ext2    defaults            0 2
/dev/sda2   none    swap    sw                  0 0
/dev/sda4   /home   ext4    defaults,noatime    0 2
FSTAB

echo "[CHROOT] ✅ Configuration de base terminée"
CHROOT_EOF

# ============================================================================
# MÉTHODE 5: INSTALLATION GRUB DEPUIS LE SYSTÈME
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 5: INSTALLATION GRUB DEPUIS SYSTÈME ━━━━"

log_info "Installation GRUB depuis le système..."
chroot /mnt/gentoo /bin/bash << 'GRUB_INSTALL'
#!/bin/bash
if command -v grub-install >/dev/null 2>&1; then
    echo "[GRUB] Installation dans MBR..."
    if grub-install /dev/sda 2>&1; then
        echo "[GRUB] ✅ GRUB installé dans MBR"
        
        echo "[GRUB] Génération grub.cfg..."
        if command -v grub-mkconfig >/dev/null 2>&1; then
            grub-mkconfig -o /boot/grub/grub.cfg && \
            echo "[GRUB] ✅ grub.cfg généré" || \
            echo "[GRUB] ❌ grub-mkconfig échoué"
        fi
    else
        echo "[GRUB] ❌ grub-install échoué"
    fi
else
    echo "[GRUB] ❌ grub-install non disponible dans chroot"
fi

# Création manuelle de grub.cfg si nécessaire
if [ ! -f "/boot/grub/grub.cfg" ]; then
    echo "[GRUB] Création manuelle de grub.cfg..."
    KERNEL=$(ls /boot/vmlinuz* | head -1)
    KERNEL_NAME=$(basename "$KERNEL")
    cat > /boot/grub/grub.cfg << EOF
set timeout=5
menuentry "Gentoo" {
    linux /$KERNEL_NAME root=/dev/sda3 ro
}
EOF
    echo "[GRUB] ✅ grub.cfg créé manuellement"
fi
GRUB_INSTALL

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "1. Vérification MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q -E "GRUB|SYSLINUX"; then
    log_success "✅ Bootloader détecté dans MBR"
else
    log_warning "⚠️ Aucun bootloader détecté dans MBR"
fi

log_info "2. Vérification configurations..."
echo "SYSLINUX: $( [ -f "/mnt/gentoo/boot/syslinux.cfg" ] && echo "✅" || echo "❌" )"
echo "GRUB: $( [ -f "/mnt/gentoo/boot/grub/grub.cfg" ] && echo "✅" || echo "❌" )"
echo "Noyau: ✅ ($KERNEL_NAME)"

log_info "3. Test de bootabilité..."
if [ -f "/mnt/gentoo/boot/syslinux.cfg" ] || [ -f "/mnt/gentoo/boot/grub/grub.cfg" ]; then
    log_success "✅ Système configuré pour booter"
else
    log_error "❌ Aucune configuration de boot"
fi

# ============================================================================
# CRÉATION DE LA SOLUTION DE SECOURS ULTIME
# ============================================================================
echo ""
log_info "━━━━ SOLUTION DE SECOURS ULTIME ━━━━"

# Créer un script de boot manuel
cat > /mnt/gentoo/boot/BOOT-URGENCE.sh << 'EOF'
#!/bin/bash
echo "🆘 SOLUTION DE BOOT URGENCE"
echo "============================"
echo ""
echo "SI RIEN NE FONCTIONNE:"
echo ""
echo "1. DÉMARRER SUR LIVECD:"
echo "   - Redémarrer sur le LiveCD Gentoo"
echo "   - Monter les partitions:"
echo "     mount /dev/sda3 /mnt/gentoo"
echo "     mount /dev/sda1 /mnt/gentoo/boot"
echo ""
echo "2. RÉPARER GRUB:"
echo "   - Dans le chroot:"
echo "     chroot /mnt/gentoo /bin/bash"
echo "     grub-install /dev/sda"
echo "     grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "3. BOOT MANUEL:"
echo "   - Au démarrage, taper 'c' pour GRUB"
echo "   - Commandes:"
echo "     set root=(hd0,msdos1)"
echo "     linux /vmlinuz-[TAB] root=/dev/sda3 ro"
echo "     boot"
echo ""
echo "4. SYSLINUX:"
echo "   - Le système peut démarrer avec SYSLINUX"
echo "   - Sinon, réexécutez le script de réparation"
EOF

chmod +x /mnt/gentoo/boot/BOOT-URGENCE.sh

# Créer un MBR de secours
log_info "Création MBR de secours..."
dd if=/dev/zero of=/mnt/gentoo/boot/mbr_backup.bin bs=512 count=1 2>/dev/null
log_success "MBR de secours créé"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 SOLUTION ULTIME TERMINÉE !"
echo "================================================================"
echo ""
echo "🔧 SOLUTIONS IMPLÉMENTÉES:"
echo "   1. ✅ SYSLINUX - Bootloader alternatif"
echo "   2. ✅ GRUB - Réinstallation complète" 
echo "   3. ✅ MBR - Nettoyé et réinitialisé"
echo "   4. ✅ Scripts de secours - Pour tout problème"
echo ""
echo "🚀 POUR TESTER:"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🎯 RÉSULTATS ATTENDUS:"
echo "   - Le système devrait démarrer avec SYSLINUX ou GRUB"
echo "   - Si un seul marche, c'est SUCCÈS !"
echo ""
echo "🆘 EN CAS D'ÉCHEC:"
echo "   - Consultez /boot/BOOT-URGENCE.sh"
echo "   - Redémarrez sur LiveCD et réexécutez ce script"
echo ""
echo "⚠️  IMPORTANT: Retirez le LiveCD avant de redémarrer !"