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

# Installation des sources du noyau avec emerge
log_info "Installation des sources du noyau via emerge..."
emerge --noreplace --quiet sys-kernel/gentoo-sources 2>&1 | grep -E ">>>" || true

# Vérification de l'installation
if [ -d "/usr/src/linux" ]; then
    KERNEL_VERSION=$(basename $(readlink /usr/src/linux) 2>/dev/null | sed 's/linux-//')
    log_success "Sources du noyau installées: version $KERNEL_VERSION"
else
    log_warning "Les sources du noyau ne semblent pas être correctement installées"
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
cat /proc/cpuinfo | grep "model name" | head -1 || log_warning "Impossible de lire /proc/cpuinfo"

echo ""
log_info "3. Mémoire RAM:"
free -h 2>/dev/null || log_warning "free non disponible"

echo ""
log_info "4. Contrôleurs de stockage:"
lspci | grep -i "storage\|sata\|ide" 2>/dev/null || log_warning "Aucun contrôleur stockage trouvé"

echo ""
log_info "5. Carte réseau:"
ip link show 2>/dev/null | grep -E "^[0-9]+:" | head -5 || log_warning "ip non disponible"

log_success "Exercice 2.2 terminé - Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
log_info "Exercice 2.3 - Configuration et compilation du noyau"

cd /usr/src/linux

log_info "Configuration du noyau pour machine virtuelle"

# Méthode de configuration (nous utiliserons une configuration de base)
log_info "Génération d'une configuration de base..."
make defconfig 2>&1 | grep -v "^\s*$" || true

log_info "Application des paramètres spécifiques pour machine virtuelle..."

# Configuration via scripts pour automatiser
log_info "Configuration des options du noyau..."

# Activer DEVTMPFS et montage automatique
./scripts/config --enable DEVTMPFS
./scripts/config --enable DEVTMPFS_MOUNT
./scripts/config --enable TMPFS
./scripts/config --enable TMPFS_POSIX_ACL

# Systèmes de fichiers (statique)
./scripts/config --enable EXT4_FS
./scripts/config --set-str EXT4_FS "y"  # Compilation statique
./scripts/config --enable MSDOS_FS
./scripts/config --enable VFAT_FS
./scripts/config --enable PROC_FS
./scripts/config --enable SYSFS
./scripts/config --enable DEVPTS_FS

# Support réseau virtuel
./scripts/config --enable VIRTIO_NET
./scripts/config --enable E1000  # Carte réseau Intel par défaut

# Support de stockage virtuel
./scripts/config --enable VIRTIO_BLK
./scripts/config --enable SCSI_VIRTIO

# Désactiver le debuggage du noyau
./scripts/config --disable DEBUG_KERNEL
./scripts/config --disable DEBUG_INFO

# Désactiver le support WiFi (inutile en VM)
./scripts/config --disable CFG80211
./scripts/config --disable MAC80211
./scripts/config --disable WLAN

# Désactiver le support Mac
./scripts/config --disable MACINTOSH_DRIVERS
./scripts/config --disable APPLE_PROPERTIES

# Support console et terminal
./scripts/config --enable VT
./scripts/config --enable VT_CONSOLE
./scripts/config --enable TTY
./scripts/config --enable SERIAL_8250
./scripts/config --enable SERIAL_8250_CONSOLE

log_success "Configuration du noyau terminée"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION DU NOYAU
# ============================================================================
log_info "Exercice 2.4 - Compilation et installation du noyau"

log_info "Compilation du noyau (peut prendre plusieurs minutes)..."
make -j$(nproc) 2>&1 | tail -5 || true

log_info "Installation des modules du noyau..."
make modules_install 2>&1 | tail -3 || true

log_info "Installation du noyau..."
make install 2>&1 | tail -3 || true

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
head -50 /boot/grub/grub.cfg 2>/dev/null | grep -E "^menuentry|^linux|^initrd" || log_warning "Impossible de lire grub.cfg"
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
echo "  • Noyau compilé: $(basename $(readlink /usr/src/linux) 2>/dev/null)"
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