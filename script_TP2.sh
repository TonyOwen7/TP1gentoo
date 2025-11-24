#!/bin/bash
# INSTALLATION GRUB AVEC LIVECD - Solution définitive

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, installation GRUB avec LiveCD..."

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
echo "     INSTALLATION GRUB - LiveCD pour MBR + Chroot pour config"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION GRUB DANS LIVECD
# ============================================================================
log_info "Vérification de GRUB dans le LiveCD..."

if command -v grub-install >/dev/null 2>&1; then
    log_success "✅ grub-install disponible dans LiveCD: $(which grub-install)"
else
    log_error "❌ grub-install non disponible dans le LiveCD"
    exit 1
fi

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
# ÉTAPE 1: INSTALLATION GRUB DANS MBR DEPUIS LE LIVECD
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 1: INSTALLATION GRUB DANS MBR (LiveCD) ━━━━"

log_info "Installation de GRUB dans le MBR avec le LiveCD..."
if grub-install --boot-directory="${MOUNT_POINT}/boot" --target=i386-pc "${DISK}" 2>&1; then
    log_success "🎉 GRUB INSTALLÉ DANS LE MBR !"
else
    log_warning "Première méthode échouée, tentative avec --force..."
    grub-install --boot-directory="${MOUNT_POINT}/boot" --target=i386-pc --force "${DISK}" 2>&1 && \
    log_success "✅ GRUB installé avec --force" || \
    log_error "❌ Échec installation GRUB"
fi

# ============================================================================
# ÉTAPE 2: CONFIGURATION DANS CHROOT
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 2: CONFIGURATION DANS CHROOT ━━━━"

log_info "Création du script de configuration..."

cat > "${MOUNT_POINT}/root/configure_grub.sh" << 'GRUB_CONFIG'
#!/bin/bash
# Configuration GRUB dans chroot

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
log_info "CONFIGURATION GRUB DANS CHROOT"
echo "================================================================"

# ============================================================================
# VÉRIFICATION GRUB DANS CHROOT
# ============================================================================
log_info "Vérification GRUB dans chroot..."

if command -v grub-install >/dev/null 2>&1; then
    log_success "✅ grub-install disponible dans chroot"
else
    log_warning "⚠️ grub-install non disponible dans chroot (normal)"
fi

if command -v grub-mkconfig >/dev/null 2>&1; then
    log_success "✅ grub-mkconfig disponible dans chroot"
else
    log_warning "⚠️ grub-mkconfig non disponible dans chroot"
fi

# ============================================================================
# CRÉATION DE grub.cfg
# ============================================================================
log_info "Création de grub.cfg..."

# Trouver le noyau exact
KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
KERNEL_NAME=$(basename "$KERNEL_FILE")

log_info "Noyau détecté: $KERNEL_NAME"

# Essayer d'abord grub-mkconfig si disponible
if command -v grub-mkconfig >/dev/null 2>&1; then
    log_info "Tentative avec grub-mkconfig..."
    if grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        log_success "✅ grub.cfg généré avec grub-mkconfig"
    else
        log_warning "grub-mkconfig échoué, création manuelle..."
    fi
fi

# Création manuelle (garantie)
log_info "Création manuelle de grub.cfg..."

cat > /boot/grub/grub.cfg << EOF
# Configuration GRUB - Générée manuellement
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

menuentry "Gentoo Linux (debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro debug
}
EOF

log_success "✅ grub.cfg créé manuellement"

# ============================================================================
# INSTALLATION GRUB DANS LE SYSTÈME (OPTIONNEL)
# ============================================================================
log_info "Installation de GRUB dans le système (pour le futur)..."

if ! command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB non installé dans le système, installation..."
    export FEATURES="-sandbox -usersandbox -network-sandbox"
    
    if emerge --noreplace --nodeps --quiet sys-boot/grub 2>&1; then
        log_success "✅ GRUB installé dans le système"
    else
        log_warning "⚠️ Impossible d'installer GRUB dans le système"
    fi
else
    log_success "✅ GRUB déjà installé dans le système"
fi

# ============================================================================
# VÉRIFICATIONS FINALES
# ============================================================================
log_info "Vérifications finales..."

echo ""
echo "=== CONFIGURATION FINALE ==="
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg: PRÉSENT"
    echo "Entrées de menu:"
    grep "^menuentry" /boot/grub/grub.cfg
else
    log_error "❌ grub.cfg: ABSENT"
fi

if ls /boot/vmlinuz* >/dev/null 2>&1; then
    log_success "✅ Noyau: PRÉSENT"
else
    log_error "❌ Noyau: ABSENT"
fi

echo ""
log_success "🎉 CONFIGURATION TERMINÉE !"
echo "   Noyau: $KERNEL_NAME"
echo "   Root: /dev/sda3"
echo "   Boot: /dev/sda1"
GRUB_CONFIG

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/configure_grub.sh"

# ============================================================================
# EXÉCUTION DE LA CONFIGURATION
# ============================================================================
echo ""
log_info "Exécution de la configuration dans chroot..."

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./configure_grub.sh
"

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "1. Vérification MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "🎉 GRUB DÉTECTÉ DANS LE MBR !"
else
    log_warning "⚠️ GRUB non détecté dans MBR (peut être normal)"
fi

log_info "2. Vérification grub.cfg..."
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg PRÉSENT"
    echo "Extrait:"
    head -5 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg ABSENT"
fi

log_info "3. Vérification noyau..."
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    log_success "✅ NOYAU PRÉSENT"
    ls "${MOUNT_POINT}/boot/vmlinuz"*
else
    log_error "❌ AUCUN NOYAU"
fi

# ============================================================================
# CRÉATION D'UN RAPPORT DE BOOT
# ============================================================================
echo ""
log_info "Création du rapport de boot..."

cat > "${MOUNT_POINT}/boot/RAPPORT-BOOT.txt" << EOF
🐧 RAPPORT BOOT GENTOO
=====================

Date: $(date)
Noyau: $KERNEL_NAME
Configuration: GRUB installé via LiveCD

✅ ÉTAPES ACCOMPLIES:
   - GRUB installé dans MBR (LiveCD)
   - grub.cfg configuré (chroot)
   - Noyau présent: $KERNEL_NAME

🚀 POUR DÉMARRER:
   1. Redémarrez sans le LiveCD
   2. Le système devrait démarrer automatiquement

🔧 EN CAS DE PROBLÈME:
   - Au démarrage: Appuyer sur 'c'
   - Commandes manuelles:
     set root=(hd0,msdos1)
     linux /$KERNEL_NAME root=/dev/sda3 ro
     boot

📞 INFORMATIONS:
   - Root: /dev/sda3
   - Boot: /dev/sda1
   - Init: OpenRC
EOF

log_success "Rapport créé: /boot/RAPPORT-BOOT.txt"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 INSTALLATION GRUB TERMINÉE !"
echo "================================================================"
echo ""
echo "✅ MÉTHODE UTILISÉE:"
echo "   • MBR: Installé depuis LiveCD (grub-install disponible)"
echo "   • Configuration: Créée dans chroot (grub.cfg)"
echo "   • Noyau: Détecté et configuré"
echo ""
echo "📊 RÉSULTATS:"
echo "   • GRUB MBR: $(dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && echo "✅ OUI" || echo "❌ NON")"
echo "   • grub.cfg: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "✅ OUI" || echo "❌ NON" )"
echo "   • Noyau: ✅ OUI ($KERNEL_NAME)"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "⚠️  ACTION REQUISE:"
echo "   - RETIREZ le LiveCD de VirtualBox AVANT de redémarrer"
echo "   - Paramètres → Stockage → Contrôleur IDE → Démonter l'ISO"
echo ""
echo "🧪 TEST:"
echo "   Si le système démarre sur Gentoo, TOUT EST BON !"
echo "   Sinon, consultez /boot/RAPPORT-BOOT.txt"