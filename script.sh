#!/bin/bash
# Script d'installation Gentoo - Du partitionnement à la configuration finale
# Utilise systemd comme système d'init

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
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"

echo "================================================================"
echo "     Installation Gentoo - Partitionnement à Configuration"
echo "================================================================"

# ============================================================================
# PARTITIONNEMENT
# ============================================================================
log_info "Partitionnement du disque ${DISK}"

(
  echo o      # Nouvelle table de partitions
  echo n; echo p; echo 1; echo ""; echo +100M    # /boot
  echo n; echo p; echo 2; echo ""; echo +256M    # swap
  echo n; echo p; echo 3; echo ""; echo +6G      # /
  echo n; echo e; echo 4; echo ""; echo ""       # /home (étendue)
  echo t; echo 2; echo 82                        # Type swap
  echo w
) | fdisk "${DISK}" >/dev/null 2>&1

sleep 2
partprobe "${DISK}" 2>/dev/null || true
log_success "Partitions créées"

# ============================================================================
# FORMATAGE
# ============================================================================
log_info "Formatage des partitions avec labels"

mkfs.ext2 -F -L boot "${DISK}1" >/dev/null 2>&1
log_success "/boot formaté (ext2)"

mkswap -L swap "${DISK}2" >/dev/null 2>&1
log_success "Swap créé"

mkfs.ext4 -F -L root "${DISK}3" >/dev/null 2>&1
log_success "/ formaté (ext4)"

mkfs.ext4 -F -L home "${DISK}4" >/dev/null 2>&1
log_success "/home formaté (ext4)"

# ============================================================================
# MONTAGE
# ============================================================================
log_info "Montage des partitions"

mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}/boot" "${MOUNT_POINT}/home"
mount "${DISK}1" "${MOUNT_POINT}/boot"
mount "${DISK}4" "${MOUNT_POINT}/home"
swapon "${DISK}2"
log_success "Toutes les partitions montées"

# ============================================================================
# TÉLÉCHARGEMENT ET EXTRACTION
# ============================================================================
log_info "Téléchargement du Stage3"
cd "${MOUNT_POINT}"
wget --quiet --show-progress "${STAGE3_URL}"
log_success "Stage3 téléchargé"

log_info "Extraction du Stage3"
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait"

log_info "Téléchargement de Portage"
cd "${MOUNT_POINT}"
wget --quiet --show-progress "${PORTAGE_URL}"
log_success "Portage téléchargé"

log_info "Extraction de Portage dans /usr"
tar xpf portage-latest.tar.xz -C "${MOUNT_POINT}/usr"
rm -f portage-latest.tar.xz
log_success "Portage installé dans /usr"

# ============================================================================
# CONFIGURATION make.conf
# ============================================================================
log_info "Configuration de make.conf"

cat >> "${MOUNT_POINT}/etc/portage/make.conf" <<'EOF'

# Configuration optimisée
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
EMERGE_DEFAULT_OPTS="--jobs=$(nproc)"
GENTOO_MIRRORS="https://mirror.init7.net/gentoo/"
USE="systemd"
EOF

log_success "make.conf configuré"

# ============================================================================
# PRÉPARATION CHROOT
# ============================================================================
log_info "Préparation du chroot"

cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
mount --bind /run "${MOUNT_POINT}/run"
mount --make-slave "${MOUNT_POINT}/run"

log_success "Environnement chroot prêt"

# ============================================================================
# CONFIGURATION DANS LE CHROOT
# ============================================================================
log_info "Entrée dans le chroot pour la configuration"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

# Configuration du dépôt
log_info "Configuration des dépôts"
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF

# Sélection du profil systemd
log_info "Sélection du profil systemd"
eselect profile list | grep systemd
PROFILE=$(eselect profile list | grep "systemd" | grep "stable" | head -1 | awk '{print $2}' | tr -d '[]')
eselect profile set ${PROFILE}
log_success "Profil systemd sélectionné"

# Configuration timezone
log_info "Configuration du fuseau horaire"
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

# Configuration locales
log_info "Configuration des locales"
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile
log_success "Locales configurées"

# Hostname
log_info "Configuration du hostname"
echo "gentoo" > /etc/hostname

# Configuration réseau pour systemd
log_info "Configuration du réseau (systemd-networkd)"
cat > /etc/systemd/network/50-dhcp.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

systemctl enable systemd-networkd
systemctl enable systemd-resolved
log_success "Réseau configuré"

# Mise à jour du système
log_info "Mise à jour du système (peut prendre du temps)"
emerge-webrsync
emerge --update --deep --newuse @world

# Installation du noyau
log_info "Installation du noyau (binaire pour gagner du temps)"
emerge sys-kernel/gentoo-kernel-bin
log_success "Noyau installé"

# Configuration fstab
log_info "Configuration de /etc/fstab"
cat > /etc/fstab <<'EOF'
# <fs>          <mountpoint>    <type>  <opts>          <dump/pass>
LABEL=boot      /boot           ext2    defaults        0 2
LABEL=root      /               ext4    defaults        0 1
LABEL=home      /home           ext4    defaults        0 2
LABEL=swap      none            swap    sw              0 0
EOF
log_success "fstab configuré"

# Installation de GRUB
log_info "Installation de GRUB"
emerge sys-boot/grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
log_success "GRUB installé et configuré"

# Mot de passe root
log_info "Configuration du mot de passe root"
echo "root:root" | chpasswd
log_success "Mot de passe root défini (mot de passe: root)"

# Création utilisateur
log_info "Création de l'utilisateur student"
useradd -m -G users,wheel,audio,video -s /bin/bash student
echo "student:student" | chpasswd

# Installation de sudo
emerge app-admin/sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
log_success "Utilisateur student créé et sudo configuré"

# Outils de base
log_info "Installation d'outils de base"
emerge net-misc/dhcpcd sys-process/htop

echo ""
echo "================================================================"
log_success "Configuration terminée avec succès !"
echo "================================================================"
echo ""
echo "Système configuré avec systemd"
echo "Comptes créés :"
echo "  - root (mot de passe: root)"
echo "  - student (mot de passe: student)"
echo ""

CHROOT_EOF

# ============================================================================
# FIN
# ============================================================================
echo ""
echo "================================================================"
log_success "Installation complète !"
echo "================================================================"
echo ""
echo "Pour terminer :"
echo "  1. Sortez du script"
echo "  2. Démontez: umount -R ${MOUNT_POINT}"
echo "  3. Redémarrez: reboot"
echo ""
log_success "Votre système Gentoo est prêt !"