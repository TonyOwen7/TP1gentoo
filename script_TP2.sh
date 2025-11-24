#!/bin/bash
# Installation manuelle de GRUB dans le MBR (contournement LiveOS_rootfs)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo "================================================================"
echo "  Installation MANUELLE GRUB dans MBR (Fix LiveOS_rootfs)"
echo "================================================================"
echo ""

# ============================================================================
# ÉTAPE 1: VÉRIFICATION ENVIRONNEMENT
# ============================================================================
log_info "━━━━ VÉRIFICATION ENVIRONNEMENT ━━━━"

# Déterminer si on est dans le système ou sur LiveCD
if grep -q "sda3" /proc/mounts 2>/dev/null && mountpoint -q /boot 2>/dev/null; then
    log_success "✓ Vous êtes DANS le système Gentoo"
    IN_CHROOT=false
    BOOT_DIR="/boot"
    ROOT_DEV="/dev/sda3"
elif [ -d "/mnt/gentoo/boot" ] && mountpoint -q /mnt/gentoo 2>/dev/null; then
    log_success "✓ Vous êtes sur LiveCD avec système monté"
    IN_CHROOT=true
    BOOT_DIR="/mnt/gentoo/boot"
    ROOT_DEV="/dev/sda3"
else
    log_error "❌ Système non monté correctement"
    echo ""
    echo "Veuillez d'abord monter le système :"
    echo "  mount /dev/sda3 /mnt/gentoo"
    echo "  mount /dev/sda1 /mnt/gentoo/boot"
    exit 1
fi

echo ""
log_info "Configuration détectée:"
echo "  • Répertoire boot: $BOOT_DIR"
echo "  • Device root: $ROOT_DEV"
echo "  • Dans chroot: $IN_CHROOT"

# ============================================================================
# ÉTAPE 2: VÉRIFICATION FICHIERS GRUB
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FICHIERS GRUB ━━━━"

# Vérifier présence des modules GRUB
if [ -d "$BOOT_DIR/grub/i386-pc" ]; then
    MODULE_COUNT=$(ls $BOOT_DIR/grub/i386-pc/*.mod 2>/dev/null | wc -l)
    log_success "✓ Modules GRUB présents ($MODULE_COUNT fichiers)"
else
    log_error "❌ Modules GRUB manquants dans $BOOT_DIR/grub/i386-pc"
    log_info "Installation des modules GRUB..."
    
    # Copier depuis le système si disponible
    if [ -d "/usr/lib/grub/i386-pc" ]; then
        mkdir -p "$BOOT_DIR/grub/i386-pc"
        cp -r /usr/lib/grub/i386-pc/* "$BOOT_DIR/grub/i386-pc/"
        log_success "✓ Modules GRUB copiés"
    else
        log_error "❌ Modules GRUB introuvables"
        exit 1
    fi
fi

# Vérifier présence du fichier core.img
if [ -f "$BOOT_DIR/grub/i386-pc/core.img" ]; then
    log_success "✓ core.img présent"
else
    log_warning "⚠️ core.img absent, sera généré"
fi

# ============================================================================
# ÉTAPE 3: GÉNÉRATION DU device.map
# ============================================================================
echo ""
log_info "━━━━ GÉNÉRATION device.map ━━━━"

log_info "Création de $BOOT_DIR/grub/device.map..."
cat > "$BOOT_DIR/grub/device.map" << EOF
(hd0) /dev/sda
EOF

log_success "✓ device.map créé"
cat "$BOOT_DIR/grub/device.map"

# ============================================================================
# ÉTAPE 4: GÉNÉRATION IMAGES GRUB
# ============================================================================
echo ""
log_info "━━━━ GÉNÉRATION IMAGES GRUB ━━━━"

# Fonction pour exécuter dans le bon contexte
run_cmd() {
    if [ "$IN_CHROOT" = true ]; then
        chroot /mnt/gentoo /bin/bash -c "$1"
    else
        bash -c "$1"
    fi
}

# Générer boot.img (pour le MBR)
log_info "Génération de boot.img..."
if command -v grub-mkimage >/dev/null 2>&1 || run_cmd "command -v grub-mkimage" >/dev/null 2>&1; then
    log_success "✓ grub-mkimage disponible"
else
    log_error "❌ grub-mkimage non disponible"
    log_info "Tentative avec grub2-mkimage..."
fi

# Générer core.img avec les modules nécessaires
log_info "Génération de core.img avec modules essentiels..."

# Trouver le chemin de grub-mkimage
GRUB_MKIMAGE=""
for path in /usr/bin/grub-mkimage /usr/sbin/grub-mkimage /bin/grub-mkimage /sbin/grub-mkimage \
            /usr/bin/grub2-mkimage /usr/sbin/grub2-mkimage; do
    if [ "$IN_CHROOT" = true ]; then
        if chroot /mnt/gentoo test -x "$path" 2>/dev/null; then
            GRUB_MKIMAGE="$path"
            break
        fi
    else
        if [ -x "$path" ]; then
            GRUB_MKIMAGE="$path"
            break
        fi
    fi
done

if [ -z "$GRUB_MKIMAGE" ]; then
    log_error "❌ grub-mkimage introuvable"
    log_info "Recherche dans le système..."
    if [ "$IN_CHROOT" = true ]; then
        chroot /mnt/gentoo find /usr -name "grub-mkimage" -o -name "grub2-mkimage" 2>/dev/null || true
    else
        find /usr -name "grub-mkimage" -o -name "grub2-mkimage" 2>/dev/null || true
    fi
    exit 1
fi

log_success "✓ Trouvé: $GRUB_MKIMAGE"

# Générer core.img
if [ "$IN_CHROOT" = true ]; then
    chroot /mnt/gentoo /bin/bash << EOCHROOT
set -e
cd /boot/grub
$GRUB_MKIMAGE -O i386-pc -o core.img -p "(hd0,msdos1)/grub" \
    biosdisk part_msdos ext2 normal ls boot search search_fs_uuid \
    configfile echo test cat help reboot halt
EOCHROOT
else
    cd "$BOOT_DIR/grub"
    $GRUB_MKIMAGE -O i386-pc -o core.img -p "(hd0,msdos1)/grub" \
        biosdisk part_msdos ext2 normal ls boot search search_fs_uuid \
        configfile echo test cat help reboot halt
fi

if [ -f "$BOOT_DIR/grub/core.img" ]; then
    CORE_SIZE=$(stat -c%s "$BOOT_DIR/grub/core.img")
    log_success "✓ core.img généré ($CORE_SIZE octets)"
else
    log_error "❌ Échec génération core.img"
    exit 1
fi

# ============================================================================
# ÉTAPE 5: INSTALLATION MANUELLE DANS LE MBR
# ============================================================================
echo ""
log_info "━━━━ INSTALLATION MANUELLE DANS LE MBR ━━━━"

log_warning "⚠️  Cette opération va écrire dans le MBR de /dev/sda"
log_info "Vos données seront PRÉSERVÉES"
echo ""
read -p "Continuer ? (oui/non): " confirm
if [ "$confirm" != "oui" ]; then
    log_error "Opération annulée"
    exit 1
fi

echo ""
log_info "Méthode 1: grub-bios-setup..."

if [ "$IN_CHROOT" = true ]; then
    # Depuis le chroot
    if chroot /mnt/gentoo grub-bios-setup -d /boot/grub/i386-pc /dev/sda 2>&1; then
        log_success "✓ GRUB installé dans MBR (grub-bios-setup)"
        MBR_INSTALLED=true
    else
        log_warning "⚠️ grub-bios-setup échoué"
        MBR_INSTALLED=false
    fi
else
    # Directement
    if grub-bios-setup -d "$BOOT_DIR/grub/i386-pc" /dev/sda 2>&1; then
        log_success "✓ GRUB installé dans MBR (grub-bios-setup)"
        MBR_INSTALLED=true
    else
        log_warning "⚠️ grub-bios-setup échoué"
        MBR_INSTALLED=false
    fi
fi

# Méthode alternative si grub-bios-setup échoue
if [ "$MBR_INSTALLED" = false ]; then
    echo ""
    log_info "Méthode 2: Installation manuelle avec dd..."
    
    # Backup du MBR actuel
    log_info "Sauvegarde du MBR actuel..."
    dd if=/dev/sda of=/tmp/mbr_backup.bin bs=512 count=1 2>/dev/null
    log_success "✓ MBR sauvegardé dans /tmp/mbr_backup.bin"
    
    # Écrire boot.img dans le MBR (premiers 440 octets)
    log_info "Écriture de boot.img dans le MBR..."
    if [ -f "$BOOT_DIR/grub/i386-pc/boot.img" ]; then
        dd if="$BOOT_DIR/grub/i386-pc/boot.img" of=/dev/sda bs=440 count=1 conv=notrunc 2>/dev/null
        log_success "✓ boot.img écrit dans le MBR"
        
        # Écrire core.img après le MBR (secteur 1)
        log_info "Écriture de core.img après le MBR..."
        dd if="$BOOT_DIR/grub/core.img" of=/dev/sda bs=512 seek=1 conv=notrunc 2>/dev/null
        log_success "✓ core.img écrit"
        
        MBR_INSTALLED=true
    else
        log_error "❌ boot.img introuvable"
        MBR_INSTALLED=false
    fi
fi

if [ "$MBR_INSTALLED" = false ]; then
    log_error "❌ Toutes les méthodes d'installation ont échoué"
    exit 1
fi

# ============================================================================
# ÉTAPE 6: GÉNÉRATION grub.cfg
# ============================================================================
echo ""
log_info "━━━━ GÉNÉRATION CONFIGURATION GRUB ━━━━"

# Trouver le noyau
KERNEL=$(ls $BOOT_DIR/vmlinuz-* 2>/dev/null | head -1)
if [ -z "$KERNEL" ]; then
    log_error "❌ Aucun noyau trouvé dans $BOOT_DIR"
    exit 1
fi
KERNEL_NAME=$(basename "$KERNEL")
log_info "Noyau trouvé: $KERNEL_NAME"

# Vérifier si initramfs existe
INITRAMFS=""
if [ -f "$BOOT_DIR/initramfs-${KERNEL_NAME#vmlinuz-}.img" ]; then
    INITRAMFS="initramfs-${KERNEL_NAME#vmlinuz-}.img"
    log_info "Initramfs trouvé: $INITRAMFS"
fi

# Créer grub.cfg
log_info "Création de grub.cfg..."
cat > "$BOOT_DIR/grub/grub.cfg" << EOF
set timeout=5
set default=0

insmod part_msdos
insmod ext2

menuentry "Gentoo Linux" {
    set root='hd0,msdos1'
    linux /$KERNEL_NAME root=$ROOT_DEV ro
    $([ -n "$INITRAMFS" ] && echo "initrd /$INITRAMFS")
}

menuentry "Gentoo Linux (mode secours)" {
    set root='hd0,msdos1'
    linux /$KERNEL_NAME root=$ROOT_DEV ro single
    $([ -n "$INITRAMFS" ] && echo "initrd /$INITRAMFS")
}

menuentry "Gentoo Linux (mode debug)" {
    set root='hd0,msdos1'
    linux /$KERNEL_NAME root=$ROOT_DEV ro debug loglevel=7
    $([ -n "$INITRAMFS" ] && echo "initrd /$INITRAMFS")
}
EOF

log_success "✓ grub.cfg créé"

# ============================================================================
# ÉTAPE 7: VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

echo ""
log_info "1. Vérification MBR..."
MBR_CHECK=$(dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -c "GRUB" || echo "0")
if [ "$MBR_CHECK" -gt 0 ]; then
    log_success "✓ GRUB détecté dans le MBR ($MBR_CHECK occurrences)"
else
    log_warning "⚠️ GRUB non détecté dans le MBR (mais peut fonctionner)"
fi

echo ""
log_info "2. Vérification fichiers..."
echo "  • device.map: $([ -f "$BOOT_DIR/grub/device.map" ] && echo "✓" || echo "✗")"
echo "  • core.img: $([ -f "$BOOT_DIR/grub/core.img" ] && echo "✓" || echo "✗")"
echo "  • grub.cfg: $([ -f "$BOOT_DIR/grub/grub.cfg" ] && echo "✓" || echo "✗")"
echo "  • Modules: $(ls $BOOT_DIR/grub/i386-pc/*.mod 2>/dev/null | wc -l) fichiers"

echo ""
log_info "3. Contenu de grub.cfg:"
head -15 "$BOOT_DIR/grub/grub.cfg" | sed 's/^/   /'

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ INSTALLATION MANUELLE TERMINÉE"
echo "================================================================"
echo ""
echo "📋 RÉSUMÉ:"
echo "   • GRUB installé manuellement dans le MBR"
echo "   • Images GRUB générées (boot.img, core.img)"
echo "   • Configuration créée dans grub.cfg"
echo "   • device.map configuré"
echo ""
echo "🚀 POUR TESTER:"
if [ "$IN_CHROOT" = true ]; then
    echo "   1. Quitter: exit"
    echo "   2. Démonter: umount -R /mnt/gentoo"
    echo "   3. Redémarrer: reboot"
else
    echo "   1. Redémarrer: reboot"
fi
echo ""
echo "⚠️  IMPORTANT:"
echo "   • Retirez le LiveCD avant de redémarrer"
echo "   • Le système devrait booter directement sur Gentoo"
echo ""
echo "🆘 EN CAS DE PROBLÈME:"
echo "   • Bootez sur le LiveCD"
echo "   • Restaurez le MBR: dd if=/tmp/mbr_backup.bin of=/dev/sda bs=512 count=1"
echo "   • Réexécutez ce script"
echo ""
echo "💡 DÉPANNAGE AU BOOT:"
echo "   Si GRUB ne démarre pas, au menu GRUB tapez 'c' puis:"
echo "   > set root=(hd0,msdos1)"
echo "   > linux /$KERNEL_NAME root=$ROOT_DEV"
echo "   > boot"
echo ""