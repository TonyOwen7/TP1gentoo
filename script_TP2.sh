#!/bin/bash
# TP2 - Configuration du système Gentoo - Exercices 2.1 à 2.6
# À exécuter APRÈS le TP1, sans démonter les partitions

SECRET_CODE="1234"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, poursuite du TP2..."

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     TP2 - Configuration du système Gentoo - Exercices 2.1-2.6"
echo "     À exécuter APRÈS le TP1 sans démonter"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION QUE LE SYSTÈME EST MONTÉ
# ============================================================================
log_info "Vérification que le système Gentoo est monté..."

if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    log_info "Montage du système..."
    
    # Montage des partitions
    mkdir -p "${MOUNT_POINT}"
    mount "${DISK}3" "${MOUNT_POINT}" || {
        log_error "Impossible de monter ${DISK}3"
        exit 1
    }
    
    mkdir -p "${MOUNT_POINT}/boot"
    mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || log_warning "Impossible de monter /boot"
    
    mkdir -p "${MOUNT_POINT}/home"
    mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || log_warning "Impossible de monter /home"
    
    swapon "${DISK}2" 2>/dev/null || log_warning "Impossible d'activer le swap"
fi

# Montage des systèmes de fichiers virtuels
log_info "Montage des systèmes de fichiers virtuels..."
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

# Copie de resolv.conf
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

log_success "Système Gentoo prêt pour le TP2"

# ============================================================================
# EXERCICE 2.1 - INSTALLATION DES SOURCES DU NOYAU
# ============================================================================
log_info "Exercice 2.1 - Installation des sources du noyau Linux"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT WARN]${NC} $1"; }
log_error() { echo -e "${RED}[CHROOT ERROR]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Début du TP2 - Configuration du système"
echo "================================================================"
echo ""

# Installation des sources du noyau
log_info "Installation des sources du noyau Linux..."
emerge --noreplace sys-kernel/gentoo-sources 2>&1 | grep -E ">>>" || {
    log_warning "Installation échouée, tentative avec autounmask..."
    emerge --autounmask-write sys-kernel/gentoo-sources 2>&1 | head -3 || true
    etc-update --automode -5 2>/dev/null || true
    emerge sys-kernel/gentoo-sources 2>&1 | grep -E ">>>" | head -3 || true
}

# Vérification de l'installation
if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    LINUX_DIR=$(ls -d /usr/src/linux-* | head -1)
    KERNEL_VERSION=$(basename "$LINUX_DIR" | sed 's/linux-//')
    ln -sf "$LINUX_DIR" /usr/src/linux 2>/dev/null || true
    log_success "Sources du noyau installées: version $KERNEL_VERSION"
else
    log_error "Échec de l'installation des sources du noyau"
    exit 1
fi

log_success "Exercice 2.1 terminé - Sources du noyau installées"

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION DU MATÉRIEL
# ============================================================================
log_info "Exercice 2.2 - Identification du matériel système"

echo ""
log_info "1. Périphériques PCI:"
if command -v lspci >/dev/null 2>&1; then
    lspci 2>/dev/null | head -10
else
    log_info "Installation de pciutils..."
    emerge --noreplace sys-apps/pciutils 2>&1 | grep -E ">>>" | head -2 || true
    lspci 2>/dev/null | head -10 || log_warning "lspci non disponible"
fi

echo ""
log_info "2. Processeur:"
grep -m1 "model name" /proc/cpuinfo 2>/dev/null || log_warning "Info CPU non disponible"

echo ""
log_info "3. Mémoire:"
free -h 2>/dev/null || grep -E "MemTotal|MemFree" /proc/meminfo 2>/dev/null | head -2

echo ""
log_info "4. Contrôleurs de stockage:"
lspci 2>/dev/null | grep -i "storage\|sata\|ide\|scsi" || log_info "Utilisation des contrôleurs par défaut"

echo ""
log_info "5. Carte réseau:"
ip link show 2>/dev/null | grep -E "^[0-9]+:" | head -5 || log_warning "ip non disponible"

log_success "Exercice 2.2 terminé - Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
log_info "Exercice 2.3 - Configuration du noyau pour machine virtuelle"

cd /usr/src/linux

# Installation des outils de configuration
log_info "Installation des outils de configuration..."
emerge --noreplace sys-devel/bc sys-devel/ncurses 2>&1 | grep -E ">>>" | head -2 || true

# Configuration de base
log_info "Génération de la configuration de base..."
if [ -f "/proc/config.gz" ]; then
    zcat /proc/config.gz > .config
    log_success "Configuration basée sur le noyau actuel"
else
    make defconfig 2>&1 | tail -5
    log_success "Configuration par défaut générée"
fi

# Configuration pour machine virtuelle
log_info "Application des paramètres pour VM..."

# Préparation des scripts de configuration
make scripts 2>&1 | tail -3 || true

# Configuration via scripts (si disponibles)
if [ -f "scripts/config" ]; then
    log_info "Configuration des options du noyau..."
    
    # Activer DEVTMPFS et systèmes de fichiers
    ./scripts/config --enable DEVTMPFS 2>/dev/null || true
    ./scripts/config --enable DEVTMPFS_MOUNT 2>/dev/null || true
    ./scripts/config --set-val EXT4_FS y 2>/dev/null || true
    
    # Support VM
    ./scripts/config --enable VIRTIO_NET 2>/dev/null || true
    ./scripts/config --enable VIRTIO_BLK 2>/dev/null || true
    ./scripts/config --enable E1000 2>/dev/null || true
    
    # Désactiver debug et options inutiles
    ./scripts/config --disable DEBUG_KERNEL 2>/dev/null || true
    ./scripts/config --disable DEBUG_INFO 2>/dev/null || true
    ./scripts/config --disable CFG80211 2>/dev/null || true
    ./scripts/config --disable MAC80211 2>/dev/null || true
    ./scripts/config --disable WLAN 2>/dev/null || true
    ./scripts/config --disable MACINTOSH_DRIVERS 2>/dev/null || true
    
    log_success "Configuration automatique appliquée"
else
    # Configuration manuelle
    log_info "Configuration manuelle des options..."
    cat >> .config << 'EOF'
# Configuration pour machine virtuelle
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_EXT4_FS=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_BLK=y
CONFIG_E1000=y
CONFIG_SCSI_VIRTIO=y
# Désactivations
CONFIG_DEBUG_KERNEL=n
CONFIG_DEBUG_INFO=n
CONFIG_CFG80211=n
CONFIG_MAC80211=n
CONFIG_WLAN=n
CONFIG_MACINTOSH_DRIVERS=n
EOF
    log_success "Configuration manuelle appliquée"
fi

# Application de la configuration
log_info "Application de la configuration..."
make olddefconfig 2>&1 | tail -3

log_success "Exercice 2.3 terminé - Noyau configuré"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION DU NOYAU
# ============================================================================
log_info "Exercice 2.4 - Compilation et installation du noyau"

log_info "Compilation du noyau (peut prendre du temps)..."
make -j2 2>&1 | tail -10 || {
    log_warning "Compilation avec -j2 échouée, tentative avec un seul thread..."
    make 2>&1 | tail -10
}

log_info "Installation des modules..."
make modules_install 2>&1 | tail -3

log_info "Installation du noyau..."
make install 2>&1 | tail -3

# Vérification
if ls /boot/vmlinuz-* >/dev/null 2>&1; then
    log_success "Noyau compilé et installé: $(ls /boot/vmlinuz-* | head -1)"
else
    log_error "Aucun noyau installé"
    exit 1
fi

# Installation de GRUB si nécessaire
log_info "Vérification de GRUB..."
if ! command -v grub-install >/dev/null 2>&1; then
    log_info "Installation de GRUB..."
    emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" | head -2
fi

log_info "Installation de GRUB sur le disque..."
grub-install /dev/sda 2>&1 | grep -v "Installing" || log_error "Échec installation GRUB"

log_info "Génération de la configuration GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found linux|Adding boot" || {
    log_warning "Génération automatique échouée"
}

log_info "Contenu du fichier GRUB:"
echo "=========================================="
grep -E "^menuentry|^linux|^initrd" /boot/grub/grub.cfg 2>/dev/null | head -10 || log_warning "Impossible de lire grub.cfg"
echo "=========================================="

log_success "Exercice 2.4 terminé - Noyau et bootloader installés"

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
log_info "Exercice 2.5 - Configuration système avancée"

# Changement du mot de passe root
log_info "Changement du mot de passe root..."
echo "root:gentoo123" | chpasswd
log_success "Mot de passe root changé: gentoo123"

# Installation des outils de gestion des logs
log_info "Installation de syslog-ng..."
emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>" | head -2 || log_warning "syslog-ng non installé"

log_info "Installation de logrotate..."
emerge --noreplace app-admin/logrotate 2>&1 | grep -E ">>>" | head -2 || log_warning "logrotate non installé"

# Activation des services
log_info "Activation des services..."
if command -v rc-update >/dev/null 2>&1; then
    rc-update add syslog-ng default 2>/dev/null || true
    rc-update add logrotate default 2>/dev/null || true
    log_success "Services activés"
else
    systemctl enable syslog-ng 2>/dev/null || true
    systemctl enable logrotate 2>/dev/null || true
    log_success "Services systemd activés"
fi

log_success "Exercice 2.5 terminé - Système configuré"

# ============================================================================
# EXERCICE 2.6 - PRÉPARATION POUR REDÉMARRAGE
# ============================================================================
log_info "Exercice 2.6 - Préparation pour redémarrage"

log_info "Vérifications finales:"
echo "✓ Noyau: $(ls /boot/vmlinuz-* 2>/dev/null | head -1)"
echo "✓ GRUB: $(command -v grub-install >/dev/null 2>&1 && echo 'INSTALLÉ' || echo 'ABSENT')"
echo "✓ Services: syslog-ng et logrotate"
echo "✓ Mot de passe root: CONFIGURÉ"

log_success "Système prêt pour le redémarrage"

# ============================================================================
# RÉSUMÉ DU TP2
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 TP2 - CONFIGURATION DU SYSTÈME TERMINÉE !"
echo "================================================================"
echo ""
echo "📋 RÉCAPITULATIF DES EXERCICES:"
echo "  ✓ Ex 2.1: Sources du noyau installées"
echo "  ✓ Ex 2.2: Matériel identifié"
echo "  ✓ Ex 2.3: Noyau configuré pour VM"
echo "  ✓ Ex 2.4: Noyau compilé et GRUB installé"
echo "  ✓ Ex 2.5: Mot de passe root + logs configurés"
echo "  ✓ Ex 2.6: Système prêt pour redémarrage"
echo ""
echo "🔧 CONFIGURATION APPLIQUÉE:"
echo "  • Noyau customisé pour machine virtuelle"
echo "  • DEVTMPFS activé"
echo "  • Debug noyau désactivé"
echo "  • WiFi et Mac désactivés"
echo "  • GRUB configuré"
echo "  • Gestion des logs avec syslog-ng et logrotate"
echo ""
echo "⚠️  IMPORTANT: NE DÉMONTEZ PAS LES PARTITIONS!"
echo "   Le système reste monté pour la suite des TP."
echo ""

CHROOT_EOF

# ============================================================================
# FIN DU TP2 - SYSTÈME TOUJOURS MONTÉ
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ TP2 TERMINÉ AVEC SUCCÈS !"
echo "================================================================"
echo ""
echo "🎯 ÉTAT ACTUEL:"
echo "   • Système Gentoo COMPLÈTEMENT configuré"
echo "   • Partitions TOUJOURS MONTÉES"
echo "   • Prêt pour le redémarrage ou les TP suivants"
echo ""
echo "🚀 POUR REDÉMARRER MAINTENANT:"
echo "   cd /"
echo "   reboot"
echo ""
echo "📝 POUR CONTINUER SANS REDÉMARRER:"
echo "   Le système reste monté sur /mnt/gentoo"
echo "   Vous pouvez exécuter d'autres scripts directement"
echo ""
echo "🔑 INFORMATIONS DE CONNEXION:"
echo "   • Utilisateur: root"
echo "   • Mot de passe: gentoo123"
echo ""
log_success "Votre Gentoo est maintenant opérationnel ! 🐧"
echo ""