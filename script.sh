#!/bin/bash
# Gentoo Installation Script - TP1 (Ex. 1.1 → 1.9)
# Version avec /home 6G et préparation OVA

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

# Variables de configuration
DISK="/dev/sda"
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     Installation automatisée de Gentoo Linux - TP1"
echo "     Configuration: /home 6G + Préparation OVA"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.2 - PARTITIONNEMENT AVEC /home 6G
# ============================================================================
log_info "EXERCICE 1.2 - Partitionnement du disque ${DISK}"

# Démontage préalable pour éviter les conflits
umount "${DISK}1" 2>/dev/null || true
umount "${DISK}2" 2>/dev/null || true
umount "${DISK}3" 2>/dev/null || true
umount "${DISK}4" 2>/dev/null || true
swapoff "${DISK}2" 2>/dev/null || true

log_info "Création des partitions avec fdisk..."
(
  echo o                          # Nouvelle table de partitions
  echo n; echo p; echo 1          # Partition 1
  echo ; echo +100M               # /boot 100M
  echo n; echo p; echo 2          # Partition 2
  echo ; echo +256M               # swap 256M
  echo n; echo p; echo 3          # Partition 3
  echo ; echo +6G                 # / 6G
  echo n; echo p; echo 4          # Partition 4
  echo ; echo +6G                 # /home 6G EXACTEMENT
  echo t; echo 2; echo 82         # Type swap
  echo w                          # Écriture
) | fdisk "${DISK}" >/dev/null 2>&1

# Attendre que le kernel détecte les nouvelles partitions
sleep 3
partprobe "${DISK}" 2>/dev/null || true
log_success "Partitions créées: /boot 100M, swap 256M, / 6G, /home 6G"

# ============================================================================
# EXERCICE 1.3 - FORMATAGE DES PARTITIONS
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

mkdir -p "${MOUNT_POINT}"

log_info "Montage de la partition racine..."
mount "${DISK}3" "${MOUNT_POINT}"
log_success "/ monté sur ${MOUNT_POINT}"

mkdir -p "${MOUNT_POINT}/boot"
log_info "Montage de /boot..."
mount "${DISK}1" "${MOUNT_POINT}/boot"
log_success "/boot monté"

mkdir -p "${MOUNT_POINT}/home"
log_info "Montage de /home..."
mount "${DISK}4" "${MOUNT_POINT}/home"
log_success "/home monté"

log_info "Activation du swap..."
swapon "${DISK}2"
log_success "Swap activé sur ${DISK}2"

# ============================================================================
# CRÉATION DU FSTAB
# ============================================================================
log_info "Génération de /etc/fstab"

mkdir -p "${MOUNT_POINT}/etc"
cat > "${MOUNT_POINT}/etc/fstab" <<'EOF'
# <fs>         <mountpoint>  <type>  <opts>              <dump/pass>
LABEL=root     /             ext4    defaults,noatime    0 1
LABEL=boot     /boot         ext2    defaults            0 2
LABEL=home     /home         ext4    defaults,noatime    0 2
LABEL=swap     none          swap    sw                  0 0
EOF

log_success "fstab créé"

# ============================================================================
# SYNCHRONISATION DE L'HORLOGE
# ============================================================================
log_info "Synchronisation de l'horloge système"

# Méthode simple pour VirtualBox
hwclock --hctosys 2>/dev/null || true
log_success "Horloge système configurée"

# ============================================================================
# EXERCICE 1.5 - TÉLÉCHARGEMENT DU STAGE3
# ============================================================================
log_info "EXERCICE 1.5 - Téléchargement du stage3 et de Portage"

cd "${MOUNT_POINT}"

# Supprimer les anciens fichiers
rm -f stage3-*.tar.xz* portage-latest.tar.xz 2>/dev/null || true

STAGE3_FILENAME="stage3-amd64-systemd-20251109T170053Z.tar.xz"

log_info "Téléchargement du stage3..."
wget --quiet --show-progress "${STAGE3_URL}" || {
  log_error "Échec du téléchargement du stage3"
  exit 1
}
log_success "Stage3 téléchargé"

log_info "Téléchargement de Portage..."
wget --quiet --show-progress "${PORTAGE_URL}" || {
  log_error "Échec du téléchargement de Portage"
  exit 1
}
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
log_success "Portage installé"

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
# EXERCICE 1.8 - CONFIGURATION DE L'ENVIRONNEMENT
# ============================================================================
log_info "EXERCICE 1.8 - Configuration de l'environnement dans le chroot"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_CMDS'
#!/bin/bash
set -euo pipefail

echo "=== DÉBUT EXERCICE 1.8 ==="

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

# Configuration réseau
echo "Configuration réseau DHCP..."
cat > /etc/conf.d/net <<'EOF'
config_eth0="dhcp"
EOF

cd /etc/init.d
ln -sf net.lo net.eth0
rc-update add net.eth0 default

echo "✅ Configuration de base terminée (Exercice 1.8)"

CHROOT_CMDS

# ============================================================================
# EXERCICE 1.9 - INSTALLATION DE HTOP
# ============================================================================
log_info "EXERCICE 1.9 - Installation de htop avec emerge"

chroot "${MOUNT_POINT}" /bin/bash <<'HTOP_CMDS'
#!/bin/bash
set -euo pipefail

echo "=== DÉBUT EXERCICE 1.9 ==="

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
# CONFIGURATION COMPLÈTE DU SYSTÈME POUR OVA
# ============================================================================
log_info "Configuration système complète pour l'export OVA"

chroot "${MOUNT_POINT}" /bin/bash <<'OVA_CMDS'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

echo "🔧 Configuration complète du système pour OVA..."

# Installation des outils essentiels
echo "Installation des outils système..."
emerge --noreplace --quiet sys-kernel/gentoo-sources
emerge --noreplace --quiet sys-kernel/genkernel
emerge --noreplace --quiet sys-boot/grub
emerge --noreplace --quiet net-misc/dhcpcd
emerge --noreplace --quiet app-admin/sudo

# Compilation du noyau
echo "Compilation du noyau (peut prendre 20-30 minutes)..."
genkernel all

# Installation de GRUB
echo "Installation de GRUB..."
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration des utilisateurs
echo "Configuration des utilisateurs..."
echo "root:gentoo" | chpasswd
useradd -m -G users,wheel -s /bin/bash etudiant
echo "etudiant:etudiant" | chpasswd

# Configuration sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Configuration des services
echo "Configuration des services..."
rc-update add dhcpcd default
rc-update add sshd default

# Script de premier démarrage pour OVA
echo "Configuration du premier démarrage..."
cat > /etc/firstboot.sh <<'EOF'
#!/bin/bash
# Script exécuté au premier démarrage après export OVA
echo "🔧 Premier démarrage - Configuration automatique..."

# Régénération des clés SSH
if [ ! -f /etc/ssh/ssh_host_key ]; then
    echo "🔑 Génération des clés SSH..."
    ssh-keygen -A
fi

# Régénération machine-id pour systemd
if [ -f /etc/machine-id ]; then
    rm /etc/machine-id
    systemd-machine-id-setup
fi

# Suppression du script après exécution
rm -f /etc/firstboot.sh
echo "✅ Configuration premier démarrage terminée"
EOF

chmod +x /etc/firstboot.sh

# Service pour premier démarrage
cat > /etc/systemd/system/firstboot.service <<'EOF'
[Unit]
Description=First Boot Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable firstboot.service

# Message de bienvenue
cat > /etc/motd <<'EOF'
=========================================
   🐧 Gentoo TP1 - ISTY ADMSYS
   Système prêt pour export OVA
=========================================
- Utilisateurs: 
    root/gentoo
    etudiant/etudiant
- Partitions: /boot 100M, / 6G, /home 6G
- Environnement français configuré
- Htop installé
=========================================
EOF

echo "✅ Système complètement configuré pour OVA"

OVA_CMDS

# ============================================================================
# NETTOYAGE ET FINALISATION POUR OVA
# ============================================================================
log_info "Nettoyage final pour OVA"

chroot "${MOUNT_POINT}" /bin/bash <<'CLEANUP_CMDS'
#!/bin/bash
set -euo pipefail

echo "🧹 Nettoyage pour OVA..."

# Nettoyage des logs et fichiers temporaires
rm -rf /var/log/*
find /var/tmp -type f -delete 2>/dev/null || true
find /tmp -type f -delete 2>/dev/null || true

# Nettoyage de l'historique
rm -f /root/.bash_history
rm -f /home/etudiant/.bash_history

# Suppression des archives téléchargées
rm -f /stage3-*.tar.xz* 2>/dev/null || true

echo "✅ Nettoyage terminé"

CLEANUP_CMDS

# ============================================================================
# DÉMONTAGE PROPRE
# ============================================================================
log_info "Démontage des partitions..."

cd /
umount -l "${MOUNT_POINT}/dev"{/shm,/pts,} 2>/dev/null || true
umount -R "${MOUNT_POINT}" 2>/dev/null || true
swapoff "${DISK}2" 2>/dev/null || true

# ============================================================================
# RAPPORT FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 TP1 COMPLÈTEMENT TERMINÉ - PRÊT POUR OVA !"
echo "================================================================"
echo ""
echo "📋 RÉCAPITULATIF :"
echo "  ✅ 1.2 - Partitionnement: /boot 100M, swap 256M, / 6G, /home 6G"
echo "  ✅ 1.3 - Formatage avec labels"
echo "  ✅ 1.4 - Montage partitions et activation swap"
echo "  ✅ 1.5 - Téléchargement stage3 et Portage"
echo "  ✅ 1.6 - Extraction des archives"
echo "  ✅ 1.7 - Environnement chroot"
echo "  ✅ 1.8 - Configuration environnement"
echo "  ✅ 1.9 - Installation htop"
echo ""
echo "🐧 SYSTÈME COMPLET :"
echo "  - Noyau compilé avec genkernel"
echo "  - GRUB installé sur /dev/sda"
echo "  - Utilisateurs: root/gentoo, etudiant/etudiant"
echo "  - Sudo configuré"
echo "  - Environnement français complet"
echo "  - Script de premier démarrage pour OVA"
echo ""
echo "🚀 POUR EXPORTER EN OVA :"
echo "1. Redémarrer sans le LiveCD"
echo "2. Démarrer sur le disque dur"
echo "3. Dans VirtualBox: Machine → Exporter en OVA"
echo ""
echo "📦 L'OVA CONSERVERA TOUT :"
echo "  - Toutes les partitions montées"
echo "  - La configuration complète"
echo "  - Les utilisateurs et mots de passe"
echo "  - Le noyau compilé et GRUB"
echo "  - Htop installé et fonctionnel"
echo ""
log_success "Exportez votre OVA et partagez votre environnement complet ! 🎯"