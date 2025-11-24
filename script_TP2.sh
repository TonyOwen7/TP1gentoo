#!/usr/bin/env bash
# fix_grub_ultimate.sh
# Installation ultime de GRUB avec contournement des erreurs

set -euo pipefail

DISK="/dev/sda"
PART_BOOT="/dev/sda1"
PART_ROOT="/dev/sda3"
MNT="/mnt/gentoo"

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_info() { echo -e "${BLUE}[i]${NC} $1"; }

[ "$(id -u)" -eq 0 ] || { log_error "Run as root!"; exit 1; }

log_info "Début de l'installation ultime de GRUB"

# Montage
log_info "Montage des partitions..."
umount -R $MNT 2>/dev/null || true
mkdir -p $MNT
mount $PART_ROOT $MNT || exit 1
mount $PART_BOOT $MNT/boot || exit 1
mount -t proc proc $MNT/proc
mount --rbind /sys $MNT/sys
mount --rbind /dev $MNT/dev

# Copie de resolv.conf
cp /etc/resolv.conf $MNT/etc/resolv.conf

log_info "Entrée dans chroot..."

chroot $MNT /bin/bash << 'EOF'
set -e

# Définir les couleurs pour le chroot
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_error() { echo -e "${RED}[CHROOT ✗]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }
log_info() { echo -e "${BLUE}[CHROOT i]${NC} $1"; }

# Mettre à jour le système et installer les paquets nécessaires
log_info "Mise à jour du système et installation des paquets..."

# Assurer que la base de données des paquets est à jour
env-update && source /etc/profile

# Installer binutils (pour strings) et grub
log_info "Installation de binutils et GRUB..."
emerge --noreplace sys-devel/binutils sys-boot/grub || {
    log_error "Échec de l'installation des paquets, tentative de résolution des dépendances..."
    emerge --oneshot binutils grub || exit 1
}

# Vérifier l'installation de strings
if ! command -v strings >/dev/null 2>&1; then
    log_error "strings n'est toujours pas installé"
    exit 1
else
    log_success "Strings est installé"
fi

# Vérifier l'installation de grub-install
if ! command -v grub-install >/dev/null 2>&1; then
    log_error "grub-install n'est pas installé"
    exit 1
fi

log_info "Installation de GRUB dans le MBR..."

# Essayer plusieurs méthodes jusqu'à ce que l'une réussisse

# Méthode 1: Installation normale
if grub-install /dev/sda; then
    log_success "GRUB installé avec succès (méthode normale)"
else
    log_warning "Échec de la méthode normale, tentative avec --skip-fs-probe"

    # Méthode 2: Skip fs probe
    if grub-install --skip-fs-probe /dev/sda; then
        log_success "GRUB installé avec --skip-fs-probe"
    else
        log_warning "Échec avec --skip-fs-probe, tentative avec target i386-pc"

        # Méthode 3: Spécifier la cible i386-pc
        if grub-install --target=i386-pc --skip-fs-probe /dev/sda; then
            log_success "GRUB installé avec target i386-pc"
        else
            log_error "Toutes les méthodes automatiques ont échoué"
            log_info "Tentative manuelle..."

            # Méthode manuelle: copier les fichiers de boot
            if [ -d "/usr/lib/grub/i386-pc" ]; then
                log_info "Copie manuelle des fichiers GRUB..."
                cp -r /usr/lib/grub/i386-pc /boot/grub/
                log_info "Écriture du bootloader dans le MBR..."
                /usr/lib/grub/i386-pc/grub-bios-setup /dev/sda
                log_success "Installation manuelle terminée"
            else
                log_error "Répertoire /usr/lib/grub/i386-pc introuvable"
                exit 1
            fi
        fi
    fi
fi

# Générer grub.cfg
log_info "Génération de grub.cfg..."
if grub-mkconfig -o /boot/grub/grub.cfg; then
    log_success "grub.cfg généré"
else
    log_warning "Échec de la génération, création manuelle de grub.cfg"
    cat > /boot/grub/grub.cfg << 'GRUB_CFG'
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro single
}
GRUB_CFG
fi

log_success "Installation de GRUB terminée dans le chroot"
EOF

# Vérification finale
log_info "Vérification finale..."
if dd if=$DISK bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "GRUB est installé dans le MBR"
else
    log_warning "GRUB n'est pas détecté dans le MBR, mais l'installation peut avoir réussi"
fi

# Nettoyage
umount -R $MNT

log_success "Processus terminé"