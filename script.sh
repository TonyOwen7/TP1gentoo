#!/bin/bash
# ISTY-ADMSYS-TP1 - Installation Gentoo complète
# Exercices 1.1 à 1.9 - Version forcée

set -euo pipefail

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Variables de configuration - UTILISE /dev/sda
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     ISTY-ADMSYS-TP1 - Installation Gentoo complète"
echo "     Version forcée - Réinstallation complète"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.2 - PARTITIONNEMENT FORCÉ
# ============================================================================
log_info "EXERCICE 1.2 - Partitionnement FORCÉ du disque ${DISK}"

# Démontage de tout ce qui est monté sur ce disque
log_info "Démontage des partitions existantes..."
umount "${DISK}1" 2>/dev/null || true
umount "${DISK}2" 2>/dev/null || true  
umount "${DISK}3" 2>/dev/null || true
umount "${DISK}4" 2>/dev/null || true
umount "${MOUNT_POINT}/boot" 2>/dev/null || true
umount "${MOUNT_POINT}/home" 2>/dev/null || true
umount "${MOUNT_POINT}" 2>/dev/null || true
swapoff "${DISK}2" 2>/dev/null || true

# Nettoyage de la table de partitions
log_info "Nettoyage de la table de partitions..."
dd if=/dev/zero of="${DISK}" bs=512 count=1 2>/dev/null || true
sleep 2

log_info "Création des partitions avec fdisk..."
log_info "Plan de partitionnement:"
log_info "  - ${DISK}1: /boot 100M ext2"
log_info "  - ${DISK}2: swap 256M" 
log_info "  - ${DISK}3: / 6G ext4"
log_info "  - ${DISK}4: /home 6G ext4"

# Création des partitions
(
    echo o                        # Nouvelle table de partitions
    echo n; echo p; echo 1        # Partition primaire 1
    echo ; echo +100M             # /boot 100M
    echo n; echo p; echo 2        # Partition primaire 2  
    echo ; echo +256M             # swap 256M
    echo n; echo p; echo 3        # Partition primaire 3
    echo ; echo +6G               # / 6G
    echo n; echo p; echo 4        # Partition primaire 4
    echo ; echo +6G               # /home 6G
    echo t; echo 2; echo 82       # Type swap
    echo w                        # Écriture
) | fdisk "${DISK}" >/dev/null 2>&1

# Attendre que le kernel détecte les nouvelles partitions
sleep 3
partprobe "${DISK}" 2>/dev/null || true
log_success "Partitions créées selon l'exercice 1.2"

# ============================================================================
# EXERCICE 1.3 - FORMATAGE AVEC LABELS
# ============================================================================
log_info "EXERCICE 1.3 - Formatage des partitions avec labels"

log_info "Formatage de /boot (ext2)..."
mkfs.ext2 -F -L boot "${DISK}1" >/dev/null 2>&1
log_success "Partition /boot formatée (ext2) avec label 'boot'"

log_info "Formatage du swap..."
mkswap -L swap "${DISK}2" >/dev/null 2>&1
log_success "Partition swap formatée avec label 'swap'"

log_info "Formatage de / (ext4)..."
mkfs.ext4 -F -L root "${DISK}3" >/dev/null 2>&1
log_success "Partition / formatée (ext4) avec label 'root'"

log_info "Formatage de /home (ext4)..."
mkfs.ext4 -F -L home "${DISK}4" >/dev/null 2>&1
log_success "Partition /home formatée (ext4) avec label 'home'"

# ============================================================================
# EXERCICE 1.4 - MONTAGE DES PARTITIONS
# ============================================================================
log_info "EXERCICE 1.4 - Montage des partitions et activation swap"

# Création des points de montage
mkdir -p "${MOUNT_POINT}"

log_info "Montage de la partition racine..."
mount "${DISK}3" "${MOUNT_POINT}"
log_success "Partition / montée sur ${MOUNT_POINT}"

mkdir -p "${MOUNT_POINT}/boot"
log_info "Montage de /boot..."
mount "${DISK}1" "${MOUNT_POINT}/boot"
log_success "Partition /boot montée"

mkdir -p "${MOUNT_POINT}/home"
log_info "Montage de /home..."
mount "${DISK}4" "${MOUNT_POINT}/home"
log_success "Partition /home montée"

log_info "Activation du swap..."
swapon "${DISK}2"
log_success "Swap activé sur ${DISK}2"

# ============================================================================
# EXERCICE 1.5 - TÉLÉCHARGEMENT STAGE3 ET PORTAGE
# ============================================================================
log_info "EXERCICE 1.5 - Téléchargement du stage3 et de Portage"

cd "${MOUNT_POINT}"

# Supprimer les anciens fichiers s'ils existent
rm -f stage3-*.tar.xz* portage-latest.tar.xz 2>/dev/null || true

# URL pour le stage3 le plus récent
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt"
ACTUAL_STAGE3_URL=$(wget -qO- "${STAGE3_URL}" | grep -v '^#' | awk '{print $1}')
STAGE3_BASE_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/${ACTUAL_STAGE3_URL}"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"

STAGE3_FILENAME=$(basename "${ACTUAL_STAGE3_URL}")

log_info "Téléchargement du stage3: ${STAGE3_FILENAME}"
wget --quiet --show-progress "${STAGE3_BASE_URL}"
log_success "Stage3 téléchargé"

log_info "Téléchargement du snapshot Portage"
wget --quiet --show-progress "${PORTAGE_URL}"
log_success "Portage téléchargé"

# ============================================================================
# EXERCICE 1.6 - EXTRACTION DES ARCHIVES
# ============================================================================
log_info "EXERCICE 1.6 - Extraction des archives"

log_info "Extraction du stage3..."
tar xpf "${STAGE3_FILENAME}" --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait avec succès"

log_info "Extraction de Portage..."
mkdir -p "${MOUNT_POINT}/var/db/repos/gentoo"
cd "${MOUNT_POINT}/var/db/repos/gentoo"
tar xpf "${MOUNT_POINT}/portage-latest.tar.xz"
rm -f "${MOUNT_POINT}/portage-latest.tar.xz"
log_success "Portage extrait dans /var/db/repos/gentoo"

# ============================================================================
# EXERCICE 1.7 - PRÉPARATION DU CHROOT
# ============================================================================
log_info "EXERCICE 1.7 - Préparation de l'environnement chroot"

mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

log_success "Environnement chroot prêt"

# ============================================================================
# EXERCICE 1.8 - CONFIGURATION DE L'ENVIRONNEMENT (CHROOT)
# ============================================================================
log_info "EXERCICE 1.8 - Configuration de l'environnement dans le chroot"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_CMDS'
#!/bin/bash
set -euo pipefail

echo "=== DÉBUT EXERCICE 1.8 DANS CHROOT ==="

# Chargement du profil
source /etc/profile
export PS1="(chroot) \$PS1"

# Configuration du clavier français
echo "Configuration du clavier français..."
echo 'keymap="fr-latin1"' > /etc/conf.d/keymaps

# Configuration des locales
echo "Configuration des locales fr_FR.UTF-8..."
cat > /etc/locale.gen <<'EOF'
fr_FR.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
locale-gen
eselect locale set fr_FR.utf8
env-update
source /etc/profile

# Configuration du hostname
echo "Configuration du nom d'hôte..."
echo "gentoo-tp1" > /etc/hostname

# Configuration du fuseau horaire
echo "Configuration du fuseau horaire Europe/Paris..."
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone

# Configuration réseau avec dhcpcd
echo "Configuration réseau DHCP..."
cat > /etc/conf.d/net <<'EOF'
config_eth0="dhcp"
EOF

cd /etc/init.d
ln -sf net.lo net.eth0
rc-update add net.eth0 default

# Configuration de /etc/fstab
echo "Configuration de /etc/fstab..."
cat > /etc/fstab <<'EOF'
# <fs>         <mountpoint>  <type>  <opts>              <dump/pass>
LABEL=root     /             ext4    defaults,noatime    0 1
LABEL=boot     /boot         ext2    defaults            0 2
LABEL=home     /home         ext4    defaults,noatime    0 2
LABEL=swap     none          swap    sw                  0 0
EOF

echo "✅ Configuration de base terminée (Exercice 1.8)"

CHROOT_CMDS

# ============================================================================
# EXERCICE 1.9 - INSTALLATION DE HTOP
# ============================================================================
log_info "EXERCICE 1.9 - Installation de htop avec emerge"

chroot "${MOUNT_POINT}" /bin/bash <<'HTOP_CMDS'
#!/bin/bash
set -euo pipefail

echo "=== DÉBUT EXERCICE 1.9 DANS CHROOT ==="

source /etc/profile
export PS1="(chroot) \$PS1"

# Configuration de Portage
echo "Configuration de Portage..."
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF

# Synchronisation de Portage
echo "Synchronisation de Portage..."
emerge-webrsync

# Installation de htop
echo "Installation de htop avec emerge..."
emerge --noreplace --quiet htop

echo "✅ htop installé avec succès - Exercice 1.9 terminé"

HTOP_CMDS

# ============================================================================
# FIN DU SCRIPT
# ============================================================================
log_success "🎉 TOUS LES EXERCICES 1.2 À 1.9 TERMINÉS AVEC SUCCÈS !"

echo ""
echo "================================================================"
echo "📋 RÉCAPITULATIF DES EXERCICES COMPLÉTÉS :"
echo "================================================================"
echo "✅ 1.2 - Partitionnement du disque /dev/sda"
echo "✅ 1.3 - Formatage avec labels" 
echo "✅ 1.4 - Montage partitions et activation swap"
echo "✅ 1.5 - Téléchargement stage3 et Portage"
echo "✅ 1.6 - Extraction des archives"
echo "✅ 1.7 - Environnement chroot"
echo "✅ 1.8 - Configuration environnement"
echo "✅ 1.9 - Installation htop"
echo ""
echo "🚀 PROCHAINES ÉTAPES MANUELLES :"
echo "   # chroot /mnt/gentoo /bin/bash"
echo "   # source /etc/profile"
echo "   # emerge gentoo-sources"
echo "   # genkernel all"
echo "   # emerge grub"
echo "   # grub-install /dev/sda"
echo "   # grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "🐧 Gentoo est maintenant installé et configuré !"