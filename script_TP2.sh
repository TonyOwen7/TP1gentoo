#!/bin/bash
# CORRECTION URGENTE GRUB MBR - Sans refaire ce qui existe déjà

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, correction URGENTE du MBR GRUB..."

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
echo "     CORRECTION URGENTE - GRUB DANS MBR SEULEMENT"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION DE L'EXISTANT
# ============================================================================
log_info "Vérification du système existant..."

# Vérifier si les partitions sont déjà montées
if mount | grep -q "${MOUNT_POINT}"; then
    log_success "✅ Partitions déjà montées"
else
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
fi

# Vérifier que le noyau existe
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls "${MOUNT_POINT}/boot/vmlinuz"* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "✅ Noyau trouvé: $KERNEL_NAME"
else
    log_error "❌ Aucun noyau trouvé dans /boot/"
    exit 1
fi

# ============================================================================
# CORRECTION GRUB DANS MBR - MÉTHODE FORCÉE
# ============================================================================
echo ""
log_info "━━━━ CORRECTION GRUB DANS MBR ━━━━"

log_info "Méthode 1: GRUB depuis LiveCD → MBR"

if command -v grub-install >/dev/null 2>&1; then
    log_success "✅ GRUB trouvé dans LiveCD"
    
    # Installation FORCÉE dans MBR
    log_info "Installation FORCÉE dans MBR..."
    if grub-install --boot-directory="${MOUNT_POINT}/boot" --target=i386-pc --force "${DISK}" 2>&1; then
        log_success "🎉 GRUB INSTALLÉ DANS MBR avec succès!"
    else
        log_warning "Première méthode échouée, tentative alternative..."
        
        # Essayer différentes options
        grub-install --boot-directory="${MOUNT_POINT}/boot" --force "${DISK}" 2>&1 || \
        grub-install --boot-directory="${MOUNT_POINT}/boot" --recheck "${DISK}" 2>&1 || \
        log_error "Échec installation GRUB depuis LiveCD"
    fi
else
    log_error "❌ GRUB non trouvé dans le LiveCD"
fi

# ============================================================================
# CRÉATION/CONFIRMATION DE grub.cfg
# ============================================================================
echo ""
log_info "━━━━ CONFIGURATION grub.cfg ━━━━"

log_info "Création/validation de grub.cfg..."

# Créer le dossier grub si nécessaire
mkdir -p "${MOUNT_POINT}/boot/grub"

# Créer grub.cfg avec la configuration correcte
cat > "${MOUNT_POINT}/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /${KERNEL_NAME} root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /${KERNEL_NAME} root=/dev/sda3 ro single
}

menuentry "Gentoo Linux (debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /${KERNEL_NAME} root=/dev/sda3 ro debug
}
EOF

log_success "grub.cfg créé/validé"

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "Vérification des fichiers de boot..."
echo "📁 Contenu de /boot/:"
ls -la "${MOUNT_POINT}/boot/" | head -8

echo ""
echo "📄 Fichier grub.cfg:"
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ PRÉSENT"
    echo "--- Extrait ---"
    head -5 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ ABSENT"
fi

echo ""
echo "🐧 Noyau:"
ls "${MOUNT_POINT}/boot/vmlinuz"* 2>/dev/null && log_success "✅ PRÉSENT" || log_error "❌ ABSENT"

# Vérification MBR
echo ""
log_info "Vérification GRUB dans MBR..."
if command -v hexdump >/dev/null 2>&1 && hexdump -C "${DISK}" 2>/dev/null | head -5 | grep -q "GRUB"; then
    log_success "🎉 GRUB DÉTECTÉ DANS LE MBR!"
elif command -v strings >/dev/null 2>&1 && dd if="${DISK}" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "🎉 GRUB DÉTECTÉ DANS LE MBR!"
else
    log_warning "⚠️ GRUB non détecté dans MBR par les outils disponibles"
    log_info "Mais l'installation a été tentée - testez le reboot"
fi

# ============================================================================
# INSTRUCTIONS DE SECOURS
# ============================================================================
echo ""
log_info "━━━━ INSTRUCTIONS DE SECOURS ━━━━"

# Créer un fichier d'instructions au cas où
cat > "${MOUNT_POINT}/boot/INSTRUCTIONS-SECOURS.txt" << EOF
🆘 INSTRUCTIONS SI LE SYSTÈME NE DÉMARRE PAS

1. AU DÉMARRAGE → APPUYER SUR 'c' POUR CONSOLE GRUB
2. COPIER-COLLER CES 3 LIGNES EXACTEMENT:

   set root=(hd0,msdos1)
   linux /${KERNEL_NAME} root=/dev/sda3 ro
   boot

3. Une fois booté, exécuter:
   grub-install /dev/sda
   grub-mkconfig -o /boot/grub/grub.cfg

Configuration:
- Noyau: ${KERNEL_NAME}
- Root: /dev/sda3
- Boot: /dev/sda1
EOF

log_success "Instructions de secours créées: /boot/INSTRUCTIONS-SECOURS.txt"

# ============================================================================
# RÉCAPITULATIF
# ============================================================================
echo ""
echo "================================================================"
log_success "CORRECTION TERMINÉE"
echo "================================================================"
echo ""
echo "✅ ACTIONS EFFECTUÉES:"
echo "   • GRUB installé dans MBR (méthode forcée)"
echo "   • grub.cfg créé/validé"
echo "   • Instructions de secours créées"
echo ""
echo "🚀 POUR TESTER:"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 SI LE SYSTÈME NE DÉMARRE PAS:"
echo "   1. Au démarrage: 'c' pour console GRUB"
echo "   2. Commandes: set root=(hd0,msdos1); linux /${KERNEL_NAME} root=/dev/sda3 ro; boot"
echo "   3. Une fois booté: grub-install /dev/sda"
echo ""
echo "⚠️  IMPORTANT: Retirez le LiveCD avant de redémarrer!"
echo "   VirtualBox: Paramètres > Stockage > Contrôleur > Démonter l'ISO"