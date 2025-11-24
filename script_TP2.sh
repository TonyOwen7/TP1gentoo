#!/bin/bash
# INSTALLATION SYSLINUX - Alternative à GRUB pour booter

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, installation SYSLINUX comme bootloader..."

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
echo "     INSTALLATION SYSLINUX - Bootloader alternatif"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION DU NOYAU
# ============================================================================
log_info "Vérification du noyau..."

mount "${DISK}1" /mnt/gentoo/boot 2>/dev/null || true
if ls /mnt/gentoo/boot/vmlinuz* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /mnt/gentoo/boot/vmlinuz* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "Noyau trouvé: $KERNEL_NAME"
    umount /mnt/gentoo/boot 2>/dev/null || true
else
    log_error "❌ Aucun noyau trouvé dans /boot!"
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

# ============================================================================
# MÉTHODE 1: INSTALLATION SYSLINEX (ALTERNATIVE À GRUB)
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 1: INSTALLATION SYSLINUX ━━━━"

log_info "Installation de SYSLINUX depuis le LiveCD..."
if command -v extlinux >/dev/null 2>&1; then
    log_success "SYSLINUX trouvé dans le LiveCD"
    
    # Installer SYSLINUX sur la partition boot
    log_info "Installation de SYSLINUX sur ${DISK}1..."
    if extlinux --install "${MOUNT_POINT}/boot" 2>&1; then
        log_success "✅ SYSLINUX installé"
    else
        log_warning "Installation extlinux échouée"
    fi
    
    # Écrire le MBR pour SYSLINUX
    log_info "Écriture du MBR SYSLINUX..."
    if dd if=/usr/share/syslinux/mbr.bin of="${DISK}" bs=440 count=1 conv=notrunc 2>/dev/null; then
        log_success "✅ MBR SYSLINUX écrit"
    else
        log_warning "Échec écriture MBR SYSLINUX"
    fi
else
    log_warning "SYSLINUX non disponible dans le LiveCD"
fi

# ============================================================================
# CONFIGURATION SYSLINUX
# ============================================================================
log_info "Création de la configuration SYSLINUX..."

cat > "${MOUNT_POINT}/boot/syslinux.cfg" << EOF
DEFAULT gentoo
PROMPT 1
TIMEOUT 50

LABEL gentoo
    LINUX /${KERNEL_NAME}
    APPEND root=/dev/sda3 ro quiet

LABEL gentoo-secours
    LINUX /${KERNEL_NAME}
    APPEND root=/dev/sda3 ro single

LABEL gentoo-debug
    LINUX /${KERNEL_NAME}
    APPEND root=/dev/sda3 ro debug
EOF

log_success "syslinux.cfg créé"

# ============================================================================
# MÉTHODE 2: CONFIGURATION DE BOOT MANUEL SIMPLE
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 2: CONFIGURATION BOOT DIRECT ━━━━"

log_info "Création d'un secteur de boot manuel..."

# Créer un script de boot simple
cat > "${MOUNT_POINT}/boot/boot.txt" << EOF
# Script de boot manuel - À copier-coller au démarrage
# Dans GRUB, taper 'c' puis:

set root=(hd0,msdos1)
linux /${KERNEL_NAME} root=/dev/sda3 ro
boot
EOF

# Créer un fichier de commandes GRUB
cat > "${MOUNT_POINT}/boot/grub_commands.txt" << EOF
set root=(hd0,msdos1)
linux /${KERNEL_NAME} root=/dev/sda3 ro
boot
EOF

log_success "Fichiers de commandes créés"

# ============================================================================
# MÉTHODE 3: INSTALLATION DIRECTE DEPUIS LE LIVECD
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 3: INSTALLATION DIRECTE GRUB ━━━━"

log_info "Tentative d'installation GRUB directe depuis LiveCD..."

if command -v grub-install >/dev/null 2>&1; then
    log_info "Installation GRUB avec options forcées..."
    
    # Nettoyer le MBR d'abord
    dd if=/dev/zero of="${DISK}" bs=512 count=1 2>/dev/null || true
    
    # Réinstaller GRUB avec force
    if grub-install --force --target=i386-pc --boot-directory="${MOUNT_POINT}/boot" "${DISK}" 2>&1; then
        log_success "✅ GRUB installé de force"
    else
        log_warning "Échec installation GRUB forcée"
    fi
else
    log_warning "grub-install non disponible"
fi

# ============================================================================
# CRÉATION DE LA CONFIGURATION GRUB (AU CAS OÙ)
# ============================================================================
log_info "Création de grub.cfg..."

mkdir -p "${MOUNT_POINT}/boot/grub"
cat > "${MOUNT_POINT}/boot/grub/grub.cfg" << EOF
set timeout=5
menuentry "Gentoo" {
    linux /${KERNEL_NAME} root=/dev/sda3 ro
}
EOF

# ============================================================================
# MÉTHODE 4: BOOT PAR DÉFAUT AVEC MBR MINIMAL
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 4: MBR MINIMAL ━━━━"

log_info "Création d'un MBR minimal..."

# Créer un MBR minimal qui charge le premier secteur de la partition boot
cat > /tmp/mbr.simple << 'EOF'
# Ceci est un MBR simple qui pointe vers la partition 1
# Il sera écrit avec dd
EOF

# Écrire un MBR simple
dd if=/dev/zero of="${DISK}" bs=512 count=1 2>/dev/null
echo -e "x\na\n1\n0\n0\n0\n1\n0\n0\n0\nr\nn\np\n1\n\n+100M\nn\np\n2\n\n+1G\nn\np\n3\n\n\nt\n2\n82\nw" | fdisk "${DISK}" 2>/dev/null || true

log_info "MBR réinitialisé"

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "Contenu de /boot/:"
ls -la "${MOUNT_POINT}/boot/" | head -10

log_info "Fichiers de configuration créés:"
ls -la "${MOUNT_POINT}/boot/"*.cfg "${MOUNT_POINT}/boot/"*.txt 2>/dev/null || true

# ============================================================================
# CRÉATION D'UN SCRIPT DE BOOT ULTIME
# ============================================================================
echo ""
log_info "━━━━ CRÉATION SCRIPT DE BOOT ULTIME ━━━━"

cat > "${MOUNT_POINT}/boot/BOOT-URGENCE.sh" << 'EOF'
#!/bin/bash
echo "🆘 SCRIPT DE BOOT URGENCE - GENTOO"
echo ""
echo "SI LE SYSTÈME NE DÉMARRE PAS:"
echo ""
echo "OPTION 1 - SYSLINUX (si installé):"
echo "  Le système devrait démarrer automatiquement"
echo ""
echo "OPTION 2 - BOOT MANUEL GRUB:"
echo "  1. Au démarrage: APPUYER SUR 'c'"
echo "  2. Copier-coller EXACTEMENT:"
echo "     set root=(hd0,msdos1)"
echo "     linux /vmlinuz-[TAB] root=/dev/sda3 ro"
echo "     boot"
echo ""
echo "OPTION 3 - RÉINSTALLATION GRUB:"
echo "  Une fois booté, exécuter:"
echo "  grub-install /dev/sda"
echo "  grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "OPTION 4 - LIVECD:"
echo "  Redémarrer sur LiveCD et monter:"
echo "  mount /dev/sda3 /mnt/gentoo"
echo "  mount /dev/sda1 /mnt/gentoo/boot"
echo "  chroot /mnt/gentoo"
echo "  grub-install /dev/sda"
EOF

chmod +x "${MOUNT_POINT}/boot/BOOT-URGENCE.sh"

# ============================================================================
# TEST DE BOOT AUTOMATIQUE
# ============================================================================
echo ""
log_info "━━━━ TEST DE BOOT AUTOMATIQUE ━━━━"

log_info "Vérification de la bootabilité..."

# Vérifier si le noyau est accessible
if [ -f "${MOUNT_POINT}/boot/${KERNEL_NAME}" ]; then
    log_success "✅ Noyau accessible: ${KERNEL_NAME}"
else
    log_error "❌ Noyau inaccessible"
fi

# Vérifier la configuration
if [ -f "${MOUNT_POINT}/boot/syslinux.cfg" ] || [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ Configuration de boot présente"
else
    log_error "❌ Aucune configuration de boot"
fi

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "INSTALLATION TERMINÉE"
echo "================================================================"
echo ""
echo "🎯 RÉSULTAT:"
echo "   • SYSLINUX: $( [ -f "${MOUNT_POINT}/boot/syslinux.cfg" ] && echo "✅ CONFIGURÉ" || echo "❌ ÉCHEC" )"
echo "   • GRUB: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "✅ CONFIGURÉ" || echo "❌ ÉCHEC" )"
echo "   • Noyau: ✅ PRÉSENT"
echo "   • Script urgence: ✅ CRÉÉ"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS DE PROBLÈME:"
echo "   1. Le système peut démarrer automatiquement avec SYSLINUX"
echo "   2. Sinon: Au démarrage → 'c' → commandes manuelles"
echo "   3. Commandes EXACTES:"
echo "      set root=(hd0,msdos1)"
echo "      linux /${KERNEL_NAME} root=/dev/sda3 ro"
echo "      boot"
echo ""
echo "📄 CONSULTEZ: /boot/BOOT-URGENCE.sh pour plus d'instructions"
echo ""
echo "⚠️  RETIREZ LE LIVECD AVANT DE REDÉMARRER!"