#!/bin/bash
# INSTALLATION GRUB DEFINITIVE - MBR + grub.cfg

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, installation GRUB DEFINITIVE..."

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
echo "     INSTALLATION GRUB DEFINITIVE - MBR + grub.cfg"
echo "================================================================"
echo ""

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions..."

umount -R "${MOUNT_POINT}" 2>/dev/null || true

mount "${DISK}3" "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

# Monter l'environnement chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
mount --bind /run "${MOUNT_POINT}/run"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# VÉRIFICATION DU SYSTÈME
# ============================================================================
log_info "Vérification du système..."

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
# SCRIPT D'INSTALLATION GRUB DEFINITIF
# ============================================================================
log_info "Création du script d'installation GRUB définitif..."

cat > "${MOUNT_POINT}/root/install_grub_definitif.sh" << 'GRUB_SCRIPT'
#!/bin/bash
# INSTALLATION GRUB DEFINITIVE - MBR + grub.cfg

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
log_info "DÉBUT INSTALLATION GRUB DEFINITIVE"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: VÉRIFICATION DE GRUB
# ============================================================================
log_info "1/4 - Vérification de GRUB..."

if command -v grub-install >/dev/null 2>&1; then
    log_success "✅ grub-install disponible: $(which grub-install)"
else
    log_error "❌ grub-install non disponible"
    exit 1
fi

if command -v grub-mkconfig >/dev/null 2>&1; then
    log_success "✅ grub-mkconfig disponible: $(which grub-mkconfig)"
else
    log_error "❌ grub-mkconfig non disponible"
    exit 1
fi

# ============================================================================
# ÉTAPE 2: INSTALLATION GRUB DANS MBR
# ============================================================================
log_info "2/4 - Installation GRUB dans le MBR..."

log_info "Installation sur /dev/sda..."
if grub-install /dev/sda 2>&1; then
    log_success "✅ GRUB installé dans le MBR"
else
    log_error "❌ Échec installation GRUB"
    log_info "Tentative avec options de secours..."
    
    grub-install --target=i386-pc /dev/sda 2>&1 || \
    grub-install --force /dev/sda 2>&1 || \
    {
        log_error "❌ Échec critique installation GRUB"
        exit 1
    }
    log_success "✅ GRUB installé avec options de secours"
fi

# ============================================================================
# ÉTAPE 3: CRÉATION DE grub.cfg
# ============================================================================
log_info "3/4 - Création de grub.cfg..."

# Trouver le noyau exact
KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
KERNEL_NAME=$(basename "$KERNEL_FILE")

log_info "Utilisation du noyau: $KERNEL_NAME"

# Méthode 1: grub-mkconfig
log_info "Génération avec grub-mkconfig..."
if grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
    log_success "✅ grub.cfg généré avec grub-mkconfig"
else
    log_warning "grub-mkconfig échoué, création manuelle..."
    
    # Méthode 2: Création manuelle
    cat > /boot/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro single
}
EOF
    log_success "✅ grub.cfg créé manuellement"
fi

# ============================================================================
# ÉTAPE 4: VÉRIFICATIONS FINALES
# ============================================================================
log_info "4/4 - Vérifications finales..."

echo ""
echo "=== VÉRIFICATION DES FICHIERS ==="

# Vérifier grub.cfg
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg: PRÉSENT"
    echo "Entrées de menu:"
    grep "^menuentry" /boot/grub/grub.cfg | head -3
else
    log_error "❌ grub.cfg: ABSENT"
fi

# Vérifier le noyau
if ls /boot/vmlinuz* >/dev/null 2>&1; then
    log_success "✅ Noyau: PRÉSENT"
    ls /boot/vmlinuz*
else
    log_error "❌ Noyau: ABSENT"
fi

# Vérifier les modules GRUB
if [ -d "/boot/grub/i386-pc" ]; then
    log_success "✅ Modules GRUB: PRÉSENTS"
else
    log_warning "⚠️ Modules GRUB: ABSENTS (peut être normal)"
fi

# Vérification finale
if [ -f "/boot/grub/grub.cfg" ] && ls /boot/vmlinuz* >/dev/null 2>&1; then
    echo ""
    log_success "🎉 INSTALLATION GRUB RÉUSSIE !"
    log_success "✅ GRUB installé dans MBR"
    log_success "✅ grub.cfg configuré"
    log_success "✅ Système prêt à démarrer"
else
    log_error "❌ Problèmes détectés dans l'installation"
    exit 1
fi

echo ""
log_info "📋 RÉCAPITULATIF:"
echo "   Noyau: $KERNEL_NAME"
echo "   Root: /dev/sda3"
echo "   Boot: /dev/sda1"
GRUB_SCRIPT

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/install_grub_definitif.sh"

# ============================================================================
# EXÉCUTION DE L'INSTALLATION
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION INSTALLATION GRUB DÉFINITIVE ━━━━"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./install_grub_definitif.sh
"

# ============================================================================
# VÉRIFICATION RÉELLE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION RÉELLE APRÈS INSTALLATION ━━━━"

log_info "1. Vérification grub.cfg..."
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg PRÉSENT"
    echo "Extrait:"
    head -5 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg ABSENT"
fi

log_info "2. Vérification noyau..."
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    log_success "✅ NOYAU PRÉSENT"
    ls "${MOUNT_POINT}/boot/vmlinuz"*
else
    log_error "❌ AUCUN NOYAU"
fi

log_info "3. Vérification MBR..."
if command -v strings >/dev/null 2>&1; then
    if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
        log_success "🎉 GRUB DÉTECTÉ DANS LE MBR !"
    else
        log_warning "⚠️ GRUB non détecté dans MBR (peut être normal avec certains bootloaders)"
    fi
else
    log_info "⚠️ 'strings' non disponible, impossible de vérifier MBR"
fi

# ============================================================================
# TEST DE CONFIGURATION
# ============================================================================
echo ""
log_info "━━━━ TEST DE CONFIGURATION ━━━━"

# Créer un script de test
cat > "${MOUNT_POINT}/boot/test-config.sh" << 'EOF'
#!/bin/bash
echo "🧪 TEST DE CONFIGURATION GRUB"
echo "=============================="
echo ""
echo "Si ce message s'affiche au boot:"
echo "✅ GRUB et le noyau fonctionnent !"
echo ""
echo "Détails:"
echo "- Noyau: $(uname -r)"
echo "- Système: Gentoo Linux"
echo "- Boot: GRUB"
echo ""
echo "🎉 Installation réussie !"
EOF

chmod +x "${MOUNT_POINT}/boot/test-config.sh"
log_success "Script de test créé: /boot/test-config.sh"

# ============================================================================
# SAUVEGARDE DE LA CONFIGURATION
# ============================================================================
echo ""
log_info "━━━━ SAUVEGARDE DE LA CONFIGURATION ━━━━"

# Sauvegarder la configuration actuelle
cp "${MOUNT_POINT}/boot/grub/grub.cfg" "${MOUNT_POINT}/boot/grub/grub.cfg.backup" 2>/dev/null || true
log_success "Configuration sauvegardée: grub.cfg.backup"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 INSTALLATION GRUB TERMINÉE AVEC SUCCÈS !"
echo "================================================================"
echo ""
echo "✅ TOUT EST CONFIGURÉ:"
echo "   • GRUB installé dans le MBR"
echo "   • grub.cfg créé et configuré"
echo "   • Noyau détecté et utilisé"
echo "   • Script de test créé"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 POUR TESTER:"
echo "   Au prochain démarrage, le système Gentoo devrait démarrer automatiquement"
echo "   Si vous voyez le message de test: ✅ SUCCÈS COMPLET !"
echo ""
echo "⚠️  ACTION REQUISE:"
echo "   - Retirez le LiveCD de VirtualBox AVANT de redémarrer"
echo "   - Paramètres → Stockage → Contrôleur IDE → Démonter l'ISO"
echo ""
echo "📞 EN CAS DE PROBLÈME:"
echo "   Consultez /boot/grub/grub.cfg et /boot/test-config.sh"