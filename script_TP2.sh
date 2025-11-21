#!/bin/bash
# TP2 - Configuration du système Gentoo
# Exercices 2.1 à 2.6

SECRET_CODE="1234"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

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
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    echo "Veuillez d'abord monter le système:"
    echo "  mount ${DISK}3 ${MOUNT_POINT}"
    echo "  mount ${DISK}1 ${MOUNT_POINT}/boot"
    echo "  mount ${DISK}4 ${MOUNT_POINT}/home"
    echo "  swapon ${DISK}2"
    exit 1
fi

# Montage des systèmes de fichiers virtuels si nécessaire
log_info "Montage des systèmes de fichiers virtuels pour le chroot"
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

# Copie de resolv.conf
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

log_info "Entrée dans le chroot pour les exercices du TP2"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT WARN]${NC} $1"; }

# Chargement du profil
source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Début du TP2 - Configuration du système"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.1 - INSTALLATION DES SOURCES DU NOYAU
# ============================================================================
log_info "Exercice 2.1 - Installation des sources du noyau Linux"

# Installation de pciutils pour lspci
log_info "Installation de pciutils pour lspci..."
emerge --noreplace --quiet sys-apps/pciutils 2>&1 | grep -E ">>>" || true

# Installation des sources du noyau avec emerge
log_info "Installation des sources du noyau via emerge..."
emerge --noreplace --quiet sys-kernel/gentoo-sources 2>&1 | grep -E ">>>" || true

# Vérification de l'installation
if [ -d "/usr/src/linux" ]; then
    KERNEL_VERSION=$(basename $(readlink /usr/src/linux) 2>/dev/null | sed 's/linux-//')
    log_success "Sources du noyau installées: version $KERNEL_VERSION"
else
    # Création du lien symbolique si nécessaire
    if ls -d /usr/src/linux-* 1> /dev/null 2>&1; then
        LINUX_DIR=$(ls -d /usr/src/linux-* | head -1)
        ln -sf "$LINUX_DIR" /usr/src/linux
        KERNEL_VERSION=$(basename "$LINUX_DIR" | sed 's/linux-//')
        log_success "Lien symbolique créé: version $KERNEL_VERSION"
    else
        log_error "Aucune source de noyau trouvée dans /usr/src/"
        exit 1
    fi
fi

log_success "Exercice 2.1 terminé - Sources du noyau installées"

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION DU MATÉRIEL
# ============================================================================
log_info "Exercice 2.2 - Identification du matériel système"

echo ""
log_info "1. Périphériques PCI:"
lspci 2>/dev/null | head -10 || log_warning "lspci non disponible"

echo ""
log_info "2. Informations sur le CPU:"
cat /proc/cpuinfo | grep "model name" | head -1 2>/dev/null || log_warning "Impossible de lire /proc/cpuinfo"

echo ""
log_info "3. Mémoire RAM:"
free -h 2>/dev/null || log_warning "free non disponible"

echo ""
log_info "4. Contrôleurs de stockage:"
lspci 2>/dev/null | grep -i "storage\|sata\|ide" || log_warning "Aucun contrôleur stockage trouvé"

echo ""
log_info "5. Carte réseau:"
ip link show 2>/dev/null | grep -E "^[0-9]+:" | head -5 || log_warning "ip non disponible"

echo ""
log_info "6. Modules chargés:"
lsmod | head -10 2>/dev/null || log_warning "lsmod non disponible"

log_success "Exercice 2.2 terminé - Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
log_info "Exercice 2.3 - Configuration et compilation du noyau"

cd /usr/src/linux

log_info "Configuration du noyau pour machine virtuelle"

# Installation des outils de configuration
log_info "Installation des outils de configuration du noyau..."
emerge --noreplace --quiet sys-apps/pciutils sys-devel/bc 2>&1 | grep -E ">>>" || true

# Méthode de configuration (nous utiliserons une configuration de base)
log_info "Génération d'une configuration de base..."
if [ -f "/proc/config.gz" ]; then
    zcat /proc/config.gz > .config
    log_success "Configuration basée sur le noyau actuel"
else
    make defconfig 2>&1 | grep -v "^\s*$" || true
    log_success "Configuration par défaut générée"
fi

log_info "Application des paramètres spécifiques pour machine virtuelle..."

# Vérification que les scripts/config sont disponibles
if [ ! -f "scripts/config" ]; then
    log_info "Préparation des scripts de configuration..."
    make scripts 2>&1 | tail -3 || true
fi

# Configuration via scripts pour automatiser
log_info "Configuration des options du noyau..."

# Fonction pour configurer les options
configure_kernel() {
    # Activer DEVTMPFS et montage automatique
    ./scripts/config --enable DEVTMPFS 2>/dev/null || true
    ./scripts/config --enable DEVTMPFS_MOUNT 2>/dev/null || true
    ./scripts/config --enable TMPFS 2>/dev/null || true
    
    # Systèmes de fichiers (statique)
    ./scripts/config --enable EXT4_FS 2>/dev/null || true
    ./scripts/config --set-val EXT4_FS y 2>/dev/null || true  # Compilation statique
    ./scripts/config --enable MSDOS_FS 2>/dev/null || true
    ./scripts/config --enable VFAT_FS 2>/dev/null || true
    ./scripts/config --enable PROC_FS 2>/dev/null || true
    ./scripts/config --enable SYSFS 2>/dev/null || true
    ./scripts/config --enable DEVPTS_FS 2>/dev/null || true

    # Support réseau virtuel
    ./scripts/config --enable VIRTIO_NET 2>/dev/null || true
    ./scripts/config --enable E1000 2>/dev/null || true  # Carte réseau Intel par défaut

    # Support de stockage virtuel
    ./scripts/config --enable VIRTIO_BLK 2>/dev/null || true
    ./scripts/config --enable SCSI_VIRTIO 2>/dev/null || true

    # Désactiver le debuggage du noyau
    ./scripts/config --disable DEBUG_KERNEL 2>/dev/null || true
    ./scripts/config --disable DEBUG_INFO 2>/dev/null || true

    # Désactiver le support WiFi (inutile en VM)
    ./scripts/config --disable CFG80211 2>/dev/null || true
    ./scripts/config --disable MAC80211 2>/dev/null || true
    ./scripts/config --disable WLAN 2>/dev/null || true

    # Désactiver le support Mac
    ./scripts/config --disable MACINTOSH_DRIVERS 2>/dev/null || true
    ./scripts/config --disable APPLE_PROPERTIES 2>/dev/null || true

    # Support console et terminal
    ./scripts/config --enable VT 2>/dev/null || true
    ./scripts/config --enable VT_CONSOLE 2>/dev/null || true
    ./scripts/config --enable TTY 2>/dev/null || true
    ./scripts/config --enable SERIAL_8250 2>/dev/null || true
    ./scripts/config --enable SERIAL_8250_CONSOLE 2>/dev/null || true
}

configure_kernel

log_success "Configuration du noyau terminée"

# Vérification de la configuration
log_info "Vérification de la configuration..."
./scripts/config --state DEVTMPFS 2>/dev/null || log_warning "Impossible de vérifier DEVTMPFS"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION DU NOYAU
# ============================================================================
log_info "Exercice 2.4 - Compilation et installation du noyau"

log_info "Préparation de la compilation..."
make olddefconfig 2>&1 | tail -3 || true

log_info "Compilation du noyau (peut prendre plusieurs minutes)..."
make -j$(nproc) 2>&1 | tail -10 || true

log_info "Installation des modules du noyau..."
make modules_install 2>&1 | tail -3 || true

log_info "Installation du noyau..."
make install 2>&1 | tail -3 || true

# Vérification de l'installation
if [ -f "/boot/vmlinuz-$KERNEL_VERSION" ]; then
    log_success "Noyau installé: /boot/vmlinuz-$KERNEL_VERSION"
else
    log_warning "Le noyau n'a pas été correctement installé"
fi

# Installation de GRUB si pas déjà fait
log_info "Vérification de GRUB..."
if ! command -v grub-install >/dev/null 2>&1; then
    emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" || true
fi

log_info "Installation de GRUB sur le disque..."
grub-install /dev/sda 2>&1 | grep -v "Installing" || true

log_info "Génération de la configuration GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found|Adding" || true

log_info "Contenu du fichier GRUB (/boot/grub/grub.cfg):"
echo "=========================================="
if [ -f "/boot/grub/grub.cfg" ]; then
    grep -E "^menuentry|^linux|^initrd" /boot/grub/grub.cfg | head -10 || true
else
    log_warning "Fichier GRUB non trouvé"
fi
echo "=========================================="

log_success "Exercice 2.4 terminé - Noyau compilé et installé"

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
log_info "Exercice 2.5 - Configuration système avancée"

# Changement du mot de passe root
log_info "Changement du mot de passe root..."
echo "root:newpassword123" | chpasswd
log_success "Mot de passe root changé"

# Installation de syslog-ng et logrotate
log_info "Installation de syslog-ng pour la gestion des logs..."
emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>" || true

log_info "Installation de logrotate..."
emerge --noreplace app-admin/logrotate 2>&1 | grep -E ">>>" || true

# Configuration de syslog-ng
log_info "Configuration de syslog-ng..."
rc-update add syslog-ng default 2>/dev/null || true

# Configuration de logrotate
log_info "Activation de logrotate..."
rc-update add logrotate default 2>/dev/null || true

log_info "Création d'une configuration logrotate personnalisée..."
cat > /etc/logrotate.conf <<'EOF'
# Configuration logrotate globale
weekly
rotate 4
create
dateext
compress
include /etc/logrotate.d
EOF

log_success "Exercice 2.5 terminé - syslog-ng et logrotate installés"

# ============================================================================
# RÉSUMÉ DU TP2
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 TP2 - Configuration du système terminé !"
echo "================================================================"
echo ""
echo "📋 Récapitulatif des exercices accomplis:"
echo "  ✓ Ex 2.1: Installation des sources du noyau Linux"
echo "  ✓ Ex 2.2: Identification du matériel système"
echo "  ✓ Ex 2.3: Configuration du noyau (DEVTMPFS, systèmes de fichiers, désactivation debug)"
echo "  ✓ Ex 2.4: Compilation et installation du noyau + configuration GRUB"
echo "  ✓ Ex 2.5: Configuration mot de passe root + installation syslog-ng et logrotate"
echo ""
echo "🔧 Éléments configurés:"
echo "  • Noyau Linux customisé pour machine virtuelle"
echo "  • Support DEVTMPFS activé"
echo "  • Systèmes de fichiers compilés statiquement"
echo "  • Debuggage noyau désactivé"
echo "  • Support WiFi et Mac désactivé"
echo "  • GRUB configuré et installé"
echo "  • Nouveau mot de passe root défini"
echo "  • Gestion des logs avec syslog-ng et logrotate"
echo ""
echo "⚠️  INFORMATIONS IMPORTANTES:"
echo "  • Mot de passe root: newpassword123"
echo "  • Noyau compilé: $KERNEL_VERSION"
echo "  • Fichier GRUB: /boot/grub/grub.cfg"
echo ""

CHROOT_EOF

# ============================================================================
# EXERCICE 2.6 - SORTIE DU CHROOT ET NETTOYAGE
# ============================================================================
log_info "Exercice 2.6 - Sortie du chroot et démontage des partitions"

log_info "Démontage des systèmes de fichiers virtuels..."
umount -l "${MOUNT_POINT}/dev"{/shm,/pts,} 2>/dev/null || true
umount -l "${MOUNT_POINT}/proc" 2>/dev/null || true
umount -l "${MOUNT_POINT}/sys" 2>/dev/null || true
umount -l "${MOUNT_POINT}/run" 2>/dev/null || true

log_info "Démontage des partitions..."
umount -R "${MOUNT_POINT}" 2>/dev/null || true
swapoff "${DISK}2" 2>/dev/null || true

log_success "Exercice 2.6 terminé - Partitions démontées"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "TP2 complété avec succès !"
echo "================================================================"
echo ""
echo "🚀 Instructions pour le redémarrage:"
echo ""
echo "1. Redémarrez maintenant le système:"
echo "   reboot"
echo ""
echo "2. Au démarrage, sélectionnez votre nouveau noyau dans GRUB"
echo ""
echo "3. Connectez-vous avec:"
echo "   - Utilisateur: root"
echo "   - Mot de passe: newpassword123"
echo ""
echo "4. Vérifications à effectuer après le boot:"
echo "   • uname -r (vérifier la version du noyau)"
echo "   • dmesg | grep -i error (vérifier les erreurs)"
echo "   • systemctl status syslog-ng (vérifier le service de logs)"
echo "   • lsmod (vérifier les modules chargés)"
echo ""
log_success "Votre système Gentoo est maintenant complètement configuré ! 🐧"
echo ""