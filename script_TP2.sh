#!/usr/bin/env bash
# fix_grub_mbr.sh
# Correction spécifique du problème MBR GRUB
# Usage: run as root

set -euo pipefail

# === Configuration ===
DISK="/dev/sda"
PART_BOOT="/dev/sda1"
PART_ROOT="/dev/sda3" 
PART_SWAP="/dev/sda2"
MNT="/mnt/gentoo"

# === Couleurs ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_info() { echo -e "${BLUE}[i]${NC} $1"; }

# === Vérification root ===
[ "$(id -u)" -eq 0 ] || { log_error "Run as root!"; exit 1; }

echo "================================================"
log_info "CORRECTION SPÉCIFIQUE MBR GRUB"
echo "================================================"

# === Diagnostic du problème ===
log_info "1. DIAGNOSTIC DU PROBLÈME MBR..."

log_info "Vérification présence GRUB dans MBR..."
if dd if=$DISK bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "GRUB détecté dans MBR"
    log_info "Le problème est ailleurs..."
    exit 0
else
    log_error "GRUB ABSENT du MBR - C'EST LE PROBLÈME!"
fi

log_info "Vérification partitions..."
[ -b "$PART_BOOT" ] && log_success "Boot: $PART_BOOT OK" || log_error "Boot: $PART_BOOT MANQUANT"
[ -b "$PART_ROOT" ] && log_success "Root: $PART_ROOT OK" || log_error "Root: $PART_ROOT MANQUANT"
[ -b "$PART_SWAP" ] && log_success "Swap: $PART_SWAP OK" || log_warning "Swap: $PART_SWAP optionnel"

# === Montage ===
log_info "2. MONTAGE DES PARTITIONS..."

umount -R $MNT 2>/dev/null || true
mkdir -p $MNT

mount $PART_ROOT $MNT || { log_error "Échec montage root"; exit 1; }
log_success "Root monté"

mkdir -p $MNT/boot
mount $PART_BOOT $MNT/boot || { log_error "Échec montage boot"; exit 1; }
log_success "Boot monté"

# Montage des systèmes virtuels
for fs in dev proc sys; do
    mount --rbind /$fs $MNT/$fs && mount --make-rslave $MNT/$fs && log_success "$fs monté" || log_error "Échec $fs"
done

cp /etc/resolv.conf $MNT/etc/resolv.conf 2>/dev/null || log_warning "resolv.conf non copié"

# === Correction dans chroot ===
log_info "3. CORRECTION DANS CHROOT..."

chroot $MNT /bin/bash << 'CHROOT_EOF'
set -e

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_error() { echo -e "${RED}[CHROOT ✗]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }
log_info() { echo -e "${BLUE}[CHROOT i]${NC} $1"; }

echo ""
log_info "=== DÉBUT CORRECTION MBR ==="

# Vérifier si GRUB est installé dans le système
if ! command -v grub-install >/dev/null 2>&1; then
    log_error "GRUB non installé dans le système"
    log_info "Installation de GRUB..."
    if emerge --noreplace sys-boot/grub; then
        log_success "GRUB installé"
    else
        log_error "Échec installation GRUB"
        exit 1
    fi
else
    GRUB_VER=$(grub-install --version | head -1)
    log_success "GRUB présent: $GRUB_VER"
fi

# Méthode 1: Installation normale
log_info "Méthode 1: Installation GRUB standard..."
if grub-install /dev/sda; then
    log_success "GRUB installé dans MBR avec succès"
else
    log_warning "Échec méthode standard, tentative méthode forcée..."
    
    # Méthode 2: Forcer l'installation
    log_info "Méthode 2: Installation forcée..."
    if grub-install --force /dev/sda; then
        log_success "GRUB installé avec --force"
    else
        log_warning "Échec méthode forcée, tentative manuelle..."
        
        # Méthode 3: Installation manuelle directe
        log_info "Méthode 3: Installation manuelle..."
        if grub-install --target=i386-pc --force /dev/sda; then
            log_success "GRUB installé avec target i386-pc"
        else
            log_error "Toutes les méthodes automatiques ont échoué"
            log_info "Tentative manuelle extrême..."
            
            # Dernière méthode: utiliser dd pour écrire le bootloader
            log_info "Recherche image boot GRUB..."
            if [ -f /usr/lib/grub/i386-pc/boot.img ]; then
                log_info "Écriture directe boot.img dans MBR..."
                dd if=/usr/lib/grub/i386-pc/boot.img of=/dev/sda bs=446 count=1
                log_success "boot.img écrit dans MBR"
            else
                log_error "Image boot GRUB non trouvée"
                exit 1
            fi
        fi
    fi
fi

# Régénérer grub.cfg
log_info "Génération grub.cfg..."
if grub-mkconfig -o /boot/grub/grub.cfg; then
    log_success "grub.cfg généré"
else
    log_warning "Échec génération grub.cfg, création manuelle..."
    cat > /boot/grub/grub.cfg << 'GRUB_CONFIG'
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (recovery)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro single
}
GRUB_CONFIG
    log_success "grub.cfg manuel créé"
fi

# Vérification finale dans chroot
log_info "Vérification finale..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✅ GRUB CONFIRMÉ DANS LE MBR"
else
    log_error "❌ GRUB TOUJOURS ABSENT DU MBR"
    exit 1
fi

log_success "Correction MBR terminée dans chroot"
CHROOT_EOF

# === Vérification finale ===
log_info "4. VÉRIFICATION FINALE HORS CHROOT..."

log_info "Vérification MBR..."
if dd if=$DISK bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✅ GRUB MAINTENANT PRÉSENT DANS MBR"
else
    log_error "❌ GRUB ABSENT DU MBR - CORRECTION ÉCHOUÉE"
    exit 1
fi

log_info "Vérification fichiers boot..."
ls -la $MNT/boot/ | grep -E "(vmlinuz|grub)" && log_success "Fichiers boot présents" || log_warning "Fichiers boot manquants"

# === Nettoyage ===
log_info "5. NETTOYAGE..."

umount -R $MNT 2>/dev/null && log_success "Système démonté" || log_warning "Échec démontage complet"

# === Rapport final ===
echo ""
echo "================================================"
log_success "CORRECTION TERMINÉE AVEC SUCCÈS!"
echo "================================================"
echo ""
log_info "RÉSUMÉ:"
echo "  • GRUB a été installé dans le MBR de $DISK"
echo "  • Configuration sauvegardée dans /boot/grub/grub.cfg"
echo "  • Le système devrait maintenant démarrer correctement"
echo ""
log_info "POUR TESTER:"
echo "  reboot"
echo ""
log_warning "Si le système ne boot toujours pas:"
echo "  1. Au démarrage, appuyer sur 'c' pour GRUB"
echo "  2. Commandes manuelles:"
echo "     set root=(hd0,msdos1)"
echo "     linux /vmlinuz root=/dev/sda3 ro"
echo "     boot"