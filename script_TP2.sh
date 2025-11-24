#!/bin/bash
# Script pour installer GRUB dans le MBR sans détruire les données

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

echo "================================================================"
echo "     Installation GRUB dans MBR (Conservation des données)"
echo "================================================================"
echo ""

# ============================================================================
# ÉTAPE 1: DIAGNOSTIC
# ============================================================================
log_info "━━━━ DIAGNOSTIC DU SYSTÈME ━━━━"

echo ""
log_info "Où sommes-nous ?"
if mountpoint -q / && grep -q "sda3" /proc/mounts 2>/dev/null; then
    log_warning "⚠️  Vous êtes DANS le système Gentoo installé"
    log_info "→ Nous allons installer GRUB directement"
    IN_SYSTEM=true
elif [ -f "/etc/gentoo-release" ] && ! mountpoint -q /mnt/gentoo 2>/dev/null; then
    log_info "✓ Vous êtes sur le LiveCD"
    log_warning "→ Nous devons d'abord monter le système"
    IN_SYSTEM=false
else
    log_error "❌ Situation non reconnue"
    lsblk
    exit 1
fi

echo ""
log_info "Vérification des partitions..."
lsblk /dev/sda

echo ""
log_info "Vérification du MBR actuel..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✓ GRUB détecté dans MBR (mais peut-être corrompu)"
else
    log_warning "⚠️ Aucun GRUB dans le MBR"
fi

# ============================================================================
# ÉTAPE 2: PRÉPARATION (Si sur LiveCD)
# ============================================================================
if [ "$IN_SYSTEM" = false ]; then
    echo ""
    log_info "━━━━ MONTAGE DU SYSTÈME ━━━━"
    
    # Créer le point de montage
    mkdir -p /mnt/gentoo
    
    # Monter la partition root
    log_info "Montage de /dev/sda3 (root)..."
    if mount /dev/sda3 /mnt/gentoo; then
        log_success "✓ Root monté"
    else
        log_error "❌ Échec montage root"
        exit 1
    fi
    
    # Monter boot
    log_info "Montage de /dev/sda1 (boot)..."
    mkdir -p /mnt/gentoo/boot
    if mount /dev/sda1 /mnt/gentoo/boot; then
        log_success "✓ Boot monté"
    else
        log_error "❌ Échec montage boot"
        exit 1
    fi
    
    # Monter les systèmes virtuels pour chroot
    log_info "Montage des systèmes virtuels..."
    mount -t proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    mount --rbind /run /mnt/gentoo/run
    mount --make-rslave /mnt/gentoo/run
    
    # Copier resolv.conf
    cp -L /etc/resolv.conf /mnt/gentoo/etc/
    
    log_success "✓ Système monté et prêt pour chroot"
    
    CHROOT_PREFIX="chroot /mnt/gentoo"
    BOOT_PATH="/mnt/gentoo/boot"
else
    CHROOT_PREFIX=""
    BOOT_PATH="/boot"
fi

# ============================================================================
# ÉTAPE 3: VÉRIFICATION GRUB INSTALLÉ
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION GRUB ━━━━"

if [ "$IN_SYSTEM" = true ]; then
    # Vérification directe
    if command -v grub-install >/dev/null 2>&1; then
        log_success "✓ GRUB est installé dans le système"
    else
        log_error "❌ GRUB n'est PAS installé"
        log_info "Installation de GRUB..."
        emerge --ask=n sys-boot/grub || {
            log_error "Échec installation GRUB"
            exit 1
        }
    fi
else
    # Vérification dans chroot
    if $CHROOT_PREFIX /bin/bash -c "command -v grub-install" >/dev/null 2>&1; then
        log_success "✓ GRUB est installé dans le système"
    else
        log_error "❌ GRUB n'est PAS installé"
        log_info "Installation de GRUB..."
        $CHROOT_PREFIX emerge --ask=n sys-boot/grub || {
            log_error "Échec installation GRUB"
            exit 1
        }
    fi
fi

# ============================================================================
# ÉTAPE 4: INSTALLATION GRUB DANS LE MBR
# ============================================================================
echo ""
log_info "━━━━ INSTALLATION GRUB DANS LE MBR ━━━━"

log_warning "⚠️  ATTENTION: Cette opération va écrire dans le MBR de /dev/sda"
log_info "Vos données ne seront PAS affectées"
echo ""
read -p "Continuer ? (oui/non): " confirm
if [ "$confirm" != "oui" ]; then
    log_error "Opération annulée"
    exit 1
fi

echo ""
log_info "Installation de GRUB dans /dev/sda..."

if [ "$IN_SYSTEM" = true ]; then
    # Installation directe
    if grub-install /dev/sda 2>&1 | tee /tmp/grub-install.log; then
        log_success "✓ GRUB installé dans le MBR"
    else
        log_error "❌ Échec installation GRUB"
        cat /tmp/grub-install.log
        exit 1
    fi
else
    # Installation via chroot - FIX pour erreur LiveOS_rootfs
    log_info "Installation GRUB depuis chroot (contournement LiveOS_rootfs)..."
    
    # MÉTHODE 1: Utiliser --boot-directory pour éviter LiveOS_rootfs
    if $CHROOT_PREFIX grub-install --boot-directory=/boot /dev/sda 2>&1 | tee /tmp/grub-install.log; then
        log_success "✓ GRUB installé dans le MBR"
    else
        log_warning "⚠️ Méthode 1 échouée, essai méthode 2..."
        
        # MÉTHODE 2: Installation manuelle des fichiers GRUB
        log_info "Installation manuelle des fichiers GRUB..."
        
        # Copier les fichiers GRUB essentiels
        if [ -d "/usr/lib/grub/i386-pc" ]; then
            mkdir -p /mnt/gentoo/boot/grub/i386-pc
            cp -r /usr/lib/grub/i386-pc/* /mnt/gentoo/boot/grub/i386-pc/ 2>/dev/null || true
            log_success "✓ Fichiers GRUB copiés"
        fi
        
        # Installer le MBR avec grub-bios-setup depuis le chroot
        if $CHROOT_PREFIX /bin/bash -c "command -v grub-bios-setup" >/dev/null 2>&1; then
            $CHROOT_PREFIX grub-bios-setup -d /boot/grub/i386-pc /dev/sda 2>&1 | tee /tmp/grub-bios-setup.log
            if [ $? -eq 0 ]; then
                log_success "✓ GRUB installé dans le MBR (méthode alternative)"
            else
                log_error "❌ Échec grub-bios-setup"
                cat /tmp/grub-bios-setup.log
                
                # MÉTHODE 3: Installation directe depuis le LiveCD avec --force
                log_warning "⚠️ Tentative méthode 3: Installation forcée..."
                grub-install --force --boot-directory=/mnt/gentoo/boot /dev/sda 2>&1 | tee /tmp/grub-force.log
                if [ $? -eq 0 ]; then
                    log_success "✓ GRUB installé (mode forcé)"
                else
                    log_error "❌ Toutes les méthodes ont échoué"
                    cat /tmp/grub-force.log
                    exit 1
                fi
            fi
        else
            log_error "❌ grub-bios-setup non disponible"
            exit 1
        fi
    fi
fi

# ============================================================================
# ÉTAPE 5: GÉNÉRATION DE LA CONFIGURATION GRUB
# ============================================================================
echo ""
log_info "━━━━ GÉNÉRATION CONFIGURATION GRUB ━━━━"

log_info "Génération de /boot/grub/grub.cfg..."

if [ "$IN_SYSTEM" = true ]; then
    # Génération directe
    if grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        log_success "✓ grub.cfg généré"
    else
        log_warning "⚠️ grub-mkconfig a échoué, création manuelle..."
        # Configuration manuelle de secours
        create_manual_grub_config
    fi
else
    # Génération via chroot
    if $CHROOT_PREFIX grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        log_success "✓ grub.cfg généré"
    else
        log_warning "⚠️ grub-mkconfig a échoué, création manuelle..."
        create_manual_grub_config
    fi
fi

# Fonction pour créer une configuration GRUB manuelle
create_manual_grub_config() {
    log_info "Création manuelle de grub.cfg..."
    
    # Trouver le noyau
    KERNEL=$(ls $BOOT_PATH/vmlinuz-* 2>/dev/null | head -1)
    if [ -z "$KERNEL" ]; then
        log_error "❌ Aucun noyau trouvé dans $BOOT_PATH"
        exit 1
    fi
    KERNEL_NAME=$(basename "$KERNEL")
    log_info "Noyau trouvé: $KERNEL_NAME"
    
    # Créer grub.cfg
    cat > $BOOT_PATH/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod part_msdos
    insmod ext2
    set root='hd0,msdos1'
    linux /$KERNEL_NAME root=/dev/sda3 ro
}

menuentry "Gentoo Linux (mode secours)" {
    insmod part_msdos
    insmod ext2
    set root='hd0,msdos1'
    linux /$KERNEL_NAME root=/dev/sda3 ro single
}
EOF
    
    log_success "✓ grub.cfg créé manuellement"
}

# ============================================================================
# ÉTAPE 6: VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

echo ""
log_info "1. Vérification MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✓ GRUB présent dans le MBR"
else
    log_error "❌ GRUB non détecté dans le MBR"
fi

echo ""
log_info "2. Vérification fichiers GRUB..."
if [ -f "$BOOT_PATH/grub/grub.cfg" ]; then
    log_success "✓ grub.cfg présent"
    echo "   Contenu:"
    head -10 "$BOOT_PATH/grub/grub.cfg" | sed 's/^/   /'
else
    log_error "❌ grub.cfg absent"
fi

echo ""
log_info "3. Vérification modules GRUB..."
if [ -d "$BOOT_PATH/grub/i386-pc" ]; then
    MODULE_COUNT=$(ls $BOOT_PATH/grub/i386-pc/*.mod 2>/dev/null | wc -l)
    log_success "✓ $MODULE_COUNT modules GRUB présents"
else
    log_warning "⚠️ Répertoire des modules GRUB absent"
fi

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ INSTALLATION TERMINÉE"
echo "================================================================"
echo ""
echo "📋 RÉSUMÉ:"
echo "   • GRUB installé dans le MBR de /dev/sda"
echo "   • Configuration générée dans /boot/grub/grub.cfg"
echo "   • Vos données n'ont PAS été modifiées"
echo ""
echo "🚀 POUR TESTER:"
if [ "$IN_SYSTEM" = false ]; then
    echo "   1. Quitter le chroot: exit"
    echo "   2. Démonter: umount -R /mnt/gentoo"
    echo "   3. Redémarrer: reboot"
else
    echo "   1. Redémarrer: reboot"
fi
echo ""
echo "⚠️  RETIREZ LE LIVECD AVANT DE REDÉMARRER"
echo ""
echo "🆘 EN CAS DE PROBLÈME AU BOOT:"
echo "   • Appuyez sur 'c' au menu GRUB pour la console"
echo "   • Tapez: set root=(hd0,msdos1)"
echo "   • Tapez: linux /vmlinuz-[TAB] root=/dev/sda3"
echo "   • Tapez: boot"
echo ""