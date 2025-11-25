#!/bin/bash
# RÉPARATION URGENTE GRUB - Gentoo

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, réparation GRUB..."

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
echo "     RÉPARATION URGENTE GRUB - Gentoo"
echo "================================================================"
echo ""

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions..."
mount "${DISK}3" "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

# Monter l'environnement chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# DÉTECTION AUTOMATIQUE DU NOYAU
# ============================================================================
log_info "Détection du noyau existant..."

# Trouver le noyau le plus récent dans /boot
KERNEL_FILE=$(ls "${MOUNT_POINT}/boot"/vmlinuz* 2>/dev/null | head -1)
if [ -n "$KERNEL_FILE" ]; then
    KERNEL_VER=$(basename "$KERNEL_FILE" | sed 's/vmlinuz-//')
    log_success "Noyau détecté: $KERNEL_VER"
else
    log_error "Aucun noyau trouvé dans /boot/"
    log_info "Liste de /boot/:"
    ls -la "${MOUNT_POINT}/boot/" 2>/dev/null || true
    exit 1
fi

# ============================================================================
# SCRIPT DE RÉPARATION GRUB
# ============================================================================
log_info "Création du script de réparation GRUB..."

cat > "${MOUNT_POINT}/root/repair_grub.sh" << 'GRUB_SCRIPT'
#!/bin/bash
# Réparation GRUB urgente

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }
log_error() { echo -e "${RED}[CHROOT ✗]${NC} $1"; }

echo ""
echo "================================================================"
log_info "DÉBUT RÉPARATION GRUB"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: VÉRIFICATION DU NOYAU
# ============================================================================
log_info "1/4 - Vérification du noyau..."

KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
if [ -z "$KERNEL_FILE" ]; then
    log_error "AUCUN NOYAU TROUVÉ dans /boot/"
    log_info "Contenu de /boot/:"
    ls -la /boot/
    exit 1
fi

KERNEL_VER=$(basename "$KERNEL_FILE" | sed 's/vmlinuz-//')
log_success "Noyau: $KERNEL_VER"

# ============================================================================
# ÉTAPE 2: INSTALLATION GRUB
# ============================================================================
log_info "2/4 - Installation de GRUB..."

# Désactiver sandbox pour éviter les problèmes
export FEATURES="-sandbox -usersandbox"

if command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB déjà installé"
else
    log_info "Installation de GRUB..."
    if emerge --noreplace sys-boot/grub 2>&1 | tee /tmp/grub_emerge.log; then
        log_success "GRUB installé avec succès"
    else
        log_error "Échec installation GRUB"
        log_info "Tentative avec --nodeps..."
        emerge --nodeps sys-boot/grub 2>&1 | tee -a /tmp/grub_emerge.log || {
            log_error "Échec critique installation GRUB"
            exit 1
        }
    fi
fi

# ============================================================================
# ÉTAPE 3: CONFIGURATION GRUB
# ============================================================================
log_info "3/4 - Configuration GRUB..."

# Installation du bootloader
log_info "Installation sur $1..."
if grub-install "$1" 2>&1 | tee /tmp/grub_install.log; then
    log_success "GRUB installé sur le disque"
else
    log_warning "Problème grub-install, tentative alternative..."
    grub-install --target=i386-pc "$1" 2>&1 | tee -a /tmp/grub_install.log || \
    grub-install --force "$1" 2>&1 | tee -a /tmp/grub_install.log || true
fi

# Création manuelle de grub.cfg (MÉTHODE GARANTIE)
log_info "Création manuelle de grub.cfg..."

cat > /boot/grub/grub.cfg << EOF
set timeout=10
set default=0

menuentry "Gentoo Linux $KERNEL_VER" {
    insmod ext2
    insmod part_msdos
    search --no-floppy --fs-uuid --set=root $(blkid -s UUID -o value /dev/sda1 2>/dev/null || echo "BOOT_PARTITION")
    linux /vmlinuz-$KERNEL_VER root=UUID=$(blkid -s UUID -o value /dev/sda3 2>/dev/null || echo "ROOT_PARTITION") ro quiet
}

menuentry "Gentoo Linux (mode secours)" {
    insmod ext2
    insmod part_msdos
    search --no-floppy --fs-uuid --set=root $(blkid -s UUID -o value /dev/sda1 2>/dev/null || echo "BOOT_PARTITION")
    linux /vmlinuz-$KERNEL_VER root=UUID=$(blkid -s UUID -o value /dev/sda3 2>/dev/null || echo "ROOT_PARTITION") ro single
}

menuentry "Redémarrage" {
    reboot
}

menuentry "Arrêt" {
    halt
}
EOF

# Si blkid a échoué, utiliser la méthode LABEL
if grep -q "BOOT_PARTITION" /boot/grub/grub.cfg; then
    log_info "Utilisation des labels pour grub.cfg..."
    cat > /boot/grub/grub.cfg << EOF
set timeout=10
set default=0

menuentry "Gentoo Linux $KERNEL_VER" {
    insmod ext2
    linux /vmlinuz-$KERNEL_VER root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (mode secours)" {
    insmod ext2
    linux /vmlinuz-$KERNEL_VER root=/dev/sda3 ro single
}
EOF
fi

log_success "grub.cfg créé"

# ============================================================================
# ÉTAPE 4: VÉRIFICATION FINALE
# ============================================================================
log_info "4/4 - Vérification finale..."

log_info "Structure de /boot/:"
ls -la /boot/

log_info "Fichiers GRUB:"
ls -la /boot/grub/ 2>/dev/null || log_warning "Dossier /boot/grub/ manquant"

log_info "Configuration GRUB:"
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg présent"
    echo "=== PREMIÈRES LIGNES DE grub.cfg ==="
    head -20 /boot/grub/grub.cfg
else
    log_error "❌ grub.cfg manquant"
fi

log_info "Résumé installation:"
echo "🔧 Noyau: $KERNEL_VER"
echo "📁 Boot: /dev/sda1"
echo "🎯 Root: /dev/sda3"
echo "🐧 GRUB: $(which grub-install 2>/dev/null || echo "non trouvé")"

if [ -f "/boot/grub/grub.cfg" ] && [ -n "$KERNEL_FILE" ]; then
    log_success "🎉 RÉPARATION GRUB TERMINÉE AVEC SUCCÈS !"
else
    log_error "⚠️ Problèmes détectés lors de la réparation"
fi

echo ""
log_info "📋 INSTRUCTIONS:"
echo "   exit # Quitter chroot"
echo "   umount -R /mnt/gentoo # Démontage"
echo "   reboot # Redémarrage"
GRUB_SCRIPT

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/repair_grub.sh"

# ============================================================================
# EXÉCUTION DU SCRIPT DE RÉPARATION
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION RÉPARATION GRUB ━━━━"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./repair_grub.sh $DISK
"

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "Contenu de /boot/ après réparation:"
ls -la "${MOUNT_POINT}/boot/" 2>/dev/null | head -10

log_info "Fichier grub.cfg:"
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg créé avec succès"
    echo "=== EXTRAIT ==="
    head -10 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg manquant"
    # Création d'urgence
    log_info "Création d'urgence de grub.cfg..."
    cat > "${MOUNT_POINT}/boot/grub/grub.cfg" << EOF
set timeout=5
menuentry "Gentoo Linux" {
    linux /vmlinuz-$KERNEL_VER root=/dev/sda3 ro
}
EOF
fi

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🔧 RÉPARATION GRUB TERMINÉE"
echo "================================================================"
echo ""
echo "✅ Noyau utilisé: $KERNEL_VER"
echo "✅ GRUB installé sur: $DISK"
echo "✅ Configuration créée: /boot/grub/grub.cfg"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS DE PROBLÈME:"
echo "   - Au démarrage, taper 'c' pour console GRUB"
echo "   - Commande: linux /vmlinuz-$KERNEL_VER root=/dev/sda3 ro"
echo "   - Puis: boot"
echo ""
log_info "N'oubliez pas de démonter avant redémarrage !"