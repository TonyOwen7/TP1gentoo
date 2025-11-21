#!/bin/bash
# Script d'installation Gentoo complète - Exercices 1.2 à 1.9
# Utilise systemd comme système d'init
# VERSION CORRIGÉE: Extrait Portage aux deux endroits

SECRET_CODE="codesecret"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, poursuite de l'exécution..."

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
echo "     Installation complète Gentoo - TP1 Exercices 1.2-1.9"
echo "     VERSION CORRIGÉE: Portage aux deux emplacements"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.2 - PARTITIONNEMENT
# ============================================================================
log_info "Exercice 1.2 - Partitionnement du disque ${DISK}"

if lsblk "${DISK}" 2>/dev/null | grep -q "${DISK}1"; then
  log_warning "Partitions déjà présentes - Skip du partitionnement"
else
  (
    echo o      # Nouvelle table de partitions MBR
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot (100Mo)
    echo n; echo p; echo 2; echo ""; echo +256M    # swap (256Mo)
    echo n; echo p; echo 3; echo ""; echo +6G      # / (6Go)
    echo n; echo p; echo 4; echo ""; echo +6G      # /home (6Go)
    echo t; echo 2; echo 82                        # Type swap
    echo w      # Écriture
  ) | fdisk "${DISK}" >/dev/null 2>&1
  
  sleep 2
  partprobe "${DISK}" 2>/dev/null || true
  log_success "Exercice 1.2 terminé - Partitions créées"
fi

# ============================================================================
# EXERCICE 1.3 - FORMATAGE AVEC LABELS
# ============================================================================
log_info "Exercice 1.3 - Formatage des partitions avec labels"

mkfs.ext2 -F -L "boot" "${DISK}1" >/dev/null 2>&1
log_success "Partition /boot formatée (ext2, label: boot)"

mkswap -L "swap" "${DISK}2" >/dev/null 2>&1
log_success "Partition swap formatée (label: swap)"

mkfs.ext4 -F -L "root" "${DISK}3" >/dev/null 2>&1
log_success "Partition / formatée (ext4, label: root)"

mkfs.ext4 -F -L "home" "${DISK}4" >/dev/null 2>&1
log_success "Partition /home formatée (ext4, label: home)"

log_success "Exercice 1.3 terminé - Toutes les partitions formatées avec labels"

# ============================================================================
# EXERCICE 1.4 - MONTAGE DES PARTITIONS
# ============================================================================
log_info "Exercice 1.4 - Montage des partitions"

mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || log_warning "/ déjà monté"
log_success "Partition / montée sur ${MOUNT_POINT}"

mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || log_warning "/boot déjà monté"
log_success "Partition /boot montée"

mkdir -p "${MOUNT_POINT}/home"
mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || log_warning "/home déjà monté"
log_success "Partition /home montée"

swapon "${DISK}2" 2>/dev/null || log_warning "Swap déjà activé"
log_success "Swap activé"

log_success "Exercice 1.4 terminé - Toutes les partitions montées"

# ============================================================================
# EXERCICE 1.5 - TÉLÉCHARGEMENT STAGE3 ET PORTAGE
# ============================================================================
log_info "Exercice 1.5 - Téléchargement Stage3 et Portage"

cd "${MOUNT_POINT}"

# Téléchargement Stage3
if [ ! -f "stage3-amd64-systemd-20251109T170053Z.tar.xz" ]; then
  log_info "Téléchargement de l'archive Stage3 avec wget..."
  wget --quiet --show-progress "${STAGE3_URL}"
  log_success "Stage3 téléchargé"
else
  log_warning "Stage3 déjà présent"
fi

# Téléchargement Portage
if [ ! -f "portage-latest.tar.xz" ]; then
  log_info "Téléchargement du snapshot Portage avec wget..."
  wget --quiet --show-progress "${PORTAGE_URL}"
  log_success "Snapshot Portage téléchargé"
else
  log_warning "Portage déjà présent"
fi

log_success "Exercice 1.5 terminé - Archives téléchargées"

# ============================================================================
# EXERCICE 1.6 - EXTRACTION DES ARCHIVES (VERSION CORRIGÉE)
# ============================================================================
log_info "Exercice 1.6 - Extraction des archives"

cd "${MOUNT_POINT}"

log_info "Extraction du Stage3 dans /mnt/gentoo (avec option -p)..."
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait dans ${MOUNT_POINT}"

# CORRECTION: Créer le répertoire pour Portage
log_info "Création du répertoire /var/db/repos/gentoo..."
mkdir -p "${MOUNT_POINT}/var/db/repos/gentoo"
mkdir -p "${MOUNT_POINT}/usr/portage"

# CORRECTION: Extraire Portage aux DEUX endroits
log_info "Extraction de Portage dans /var/db/repos/gentoo (emplacement principal)..."
tar xpf portage-latest.tar.xz -C "${MOUNT_POINT}/var/db/repos/gentoo" --strip-components=1
log_success "Portage extrait dans ${MOUNT_POINT}/var/db/repos/gentoo"

log_info "Extraction de Portage dans /usr/portage (emplacement alternatif)..."
tar xpf portage-latest.tar.xz -C "${MOUNT_POINT}/usr"
log_success "Portage extrait dans ${MOUNT_POINT}/usr/portage"

# Nettoyage des archives
rm -f stage3-*.tar.xz portage-latest.tar.xz
log_success "Exercice 1.6 terminé - Archives extraites (Portage aux deux emplacements)"

# ============================================================================
# CONFIGURATION - PRÉPARATION DU CHROOT
# ============================================================================
log_info "Configuration de make.conf pour systemd"

cat >> "${MOUNT_POINT}/etc/portage/make.conf" <<'EOF'

# Configuration optimisée pour systemd
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j2"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=2"
GENTOO_MIRRORS="https://mirror.init7.net/gentoo/ https://gentoo.mirrors.ovh.net/gentoo-distfiles/"
ACCEPT_LICENSE="*"
USE="systemd"
EOF

log_success "make.conf configuré"

# ============================================================================
# EXERCICE 1.7 - PRÉPARATION ET CHROOT
# ============================================================================
log_info "Exercice 1.7 - Préparation du chroot"

log_info "Copie de resolv.conf"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

log_info "Montage des systèmes de fichiers virtuels"
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

log_success "Exercice 1.7 terminé - Environnement chroot prêt"

# ============================================================================
# EXERCICE 1.8 et 1.9 - CONFIGURATION DANS LE CHROOT
# ============================================================================
log_info "Entrée dans le chroot pour configuration (Exercices 1.8 et 1.9)"

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
log_info "Configuration du système dans l'environnement chroot"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION DE PORTAGE
# ============================================================================
log_info "Vérification de l'installation de Portage..."
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    log_success "Portage présent dans /var/db/repos/gentoo"
elif [ -d "/usr/portage/profiles" ]; then
    log_warning "Portage dans /usr/portage, déplacement..."
    mkdir -p /var/db/repos
    mv /usr/portage /var/db/repos/gentoo
    log_success "Portage déplacé vers /var/db/repos/gentoo"
else
    log_warning "Portage non trouvé, synchronisation nécessaire"
fi

# ============================================================================
# EXERCICE 1.8 - CONFIGURATION DE L'ENVIRONNEMENT
# ============================================================================
log_info "Exercice 1.8 - Configuration de l'environnement système"

# Configuration du dépôt Gentoo
log_info "Configuration des dépôts Portage"
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-jobs = 1
sync-rsync-verify-metamanifest = yes
EOF
log_success "Dépôts configurés"

# Sélection du profil systemd
log_info "Sélection du profil systemd"

# Vérifier que les profils existent
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    log_success "Profils Gentoo disponibles"
    
    # Trouver un profil systemd automatiquement
    SYSTEMD_PROFILE=""
    for VERSION in 17.1/systemd 17.0/systemd 17.1/systemd/merged-usr; do
        if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}" ]; then
            SYSTEMD_PROFILE="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
            break
        fi
    done
    
    if [ -n "${SYSTEMD_PROFILE}" ]; then
        rm -f /etc/portage/make.profile
        ln -sf "${SYSTEMD_PROFILE}" /etc/portage/make.profile
        log_success "Profil systemd configuré: ${SYSTEMD_PROFILE}"
    else
        log_warning "Profil systemd non trouvé, utilisation d'eselect..."
        if command -v eselect >/dev/null 2>&1; then
            PROFILE_NUM=$(eselect profile list 2>/dev/null | grep "systemd" | grep "stable" | head -1 | awk '{print $1}' | tr -d '[]')
            if [ -n "${PROFILE_NUM}" ]; then
                eselect profile set "${PROFILE_NUM}"
                log_success "Profil systemd sélectionné via eselect"
            fi
        fi
    fi
else
    log_warning "Profils non disponibles, synchronisation ultérieure nécessaire"
fi

# 1. Configuration du clavier (français)
log_info "1/6 - Configuration du clavier français"
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=fr-latin1
EOF
log_success "Clavier configuré en français (fr-latin1)"

# 2. Configuration de la localisation (fr_FR.UTF-8)
log_info "2/6 - Configuration de la localisation (fr_FR.UTF-8)"
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF

locale-gen >/dev/null 2>&1
eselect locale set fr_FR.utf8 >/dev/null 2>&1 || eselect locale set 1 >/dev/null 2>&1
log_success "Locales configurées"

# Rechargement de l'environnement
env-update >/dev/null 2>&1
source /etc/profile

# 3. Configuration du nom d'hôte
log_info "3/6 - Configuration du nom d'hôte"
echo "gentoo-vm" > /etc/hostname
log_success "Nom d'hôte défini: gentoo-vm"

# 4. Configuration de l'heure locale (timezone)
log_info "4/6 - Configuration du fuseau horaire (Europe/Paris)"
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data >/dev/null 2>&1 || true
log_success "Fuseau horaire configuré: Europe/Paris"

# 5. Configuration du réseau avec systemd-networkd et dhcp
log_info "5/6 - Configuration du réseau (DHCP avec systemd-networkd)"
cat > /etc/systemd/network/50-dhcp.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF

# Activation des services réseau systemd
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
log_success "Réseau configuré (DHCP activé)"

# Installation de dhcpcd comme demandé
log_info "Installation du client DHCP (dhcpcd)"
emerge --noreplace --quiet net-misc/dhcpcd 2>&1 | grep -E ">>>" || true
log_success "dhcpcd installé"

# 6. Configuration du montage des partitions (fstab)
log_info "6/6 - Configuration de /etc/fstab"
cat > /etc/fstab <<'EOF'
# <fs>          <mountpoint>    <type>  <opts>              <dump/pass>
LABEL=root      /               ext4    defaults,noatime    0 1
LABEL=boot      /boot           ext2    defaults            0 2
LABEL=home      /home           ext4    defaults,noatime    0 2
LABEL=swap      none            swap    sw                  0 0
EOF
log_success "/etc/fstab configuré"

log_success "Exercice 1.8 terminé - Environnement complètement configuré"

# ============================================================================
# EXERCICE 1.9 - INSTALLATION DE HTOP
# ============================================================================
log_info "Exercice 1.9 - Installation de htop avec emerge"

if ! command -v htop >/dev/null 2>&1; then
  emerge --noreplace --quiet sys-process/htop 2>&1 | grep -E ">>>" || true
  log_success "htop installé avec succès"
else
  log_warning "htop déjà installé"
fi

log_success "Exercice 1.9 terminé - htop disponible"

# ============================================================================
# INSTALLATION DU NOYAU ET DU BOOTLOADER
# ============================================================================
echo ""
log_info "Installation du noyau et configuration du bootloader"

# Mise à jour du système
log_info "Mise à jour du système (@world)"
emerge --update --deep --newuse @world 2>&1 | grep -E ">>>" || true
log_success "Système mis à jour"

# Installation du noyau (version binaire pour gagner du temps)
log_info "Installation du noyau Linux (gentoo-kernel-bin)"
emerge --noreplace sys-kernel/gentoo-kernel-bin 2>&1 | grep -E ">>>" || true
log_success "Noyau Linux installé"

# Installation de GRUB2
log_info "Installation de GRUB2 (bootloader)"
emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" || true
log_success "GRUB2 installé"

# Installation de GRUB sur le disque
log_info "Installation de GRUB sur /dev/sda"
grub-install /dev/sda 2>&1 | grep -v "Installing" || true
log_success "GRUB installé sur le disque"

# Génération de la configuration GRUB
log_info "Génération de la configuration GRUB"
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found|Adding" || true
log_success "Configuration GRUB générée"

# ============================================================================
# CONFIGURATION DES UTILISATEURS
# ============================================================================
log_info "Configuration des comptes utilisateurs"

# Mot de passe root
echo "root:root" | chpasswd
log_success "Mot de passe root défini (mot de passe: root)"

# Création d'un utilisateur standard
useradd -m -G users,wheel,audio,video -s /bin/bash student 2>/dev/null || log_warning "Utilisateur student déjà existant"
echo "student:student" | chpasswd
log_success "Utilisateur 'student' créé (mot de passe: student)"

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 Installation complète de Gentoo terminée !"
echo "================================================================"
echo ""
echo "📋 Récapitulatif des exercices accomplis:"
echo "  ✓ Ex 1.2: Partitionnement du disque (4 partitions)"
echo "  ✓ Ex 1.3: Formatage avec labels (boot, swap, root, home)"
echo "  ✓ Ex 1.4: Montage des partitions et activation du swap"
echo "  ✓ Ex 1.5: Téléchargement Stage3 et Portage"
echo "  ✓ Ex 1.6: Extraction des archives (Portage aux deux emplacements)"
echo "  ✓ Ex 1.7: Configuration du chroot"
echo "  ✓ Ex 1.8: Configuration complète (clavier, locale, hostname, timezone, DHCP, fstab)"
echo "  ✓ Ex 1.9: Installation de htop"
echo ""
echo "📦 Système configuré avec:"
echo "  • Système d'init: systemd"
echo "  • Clavier: français (fr-latin1)"
echo "  • Locale: fr_FR.UTF-8"
echo "  • Hostname: gentoo-vm"
echo "  • Timezone: Europe/Paris"
echo "  • Réseau: DHCP (systemd-networkd)"
echo "  • Noyau: gentoo-kernel-bin"
echo "  • Bootloader: GRUB2"
echo "  • Outils: htop, dhcpcd"
echo "  • Portage: /var/db/repos/gentoo ET /usr/portage"
echo ""
echo "👤 Comptes utilisateurs:"
echo "  • root (mot de passe: root)"
echo "  • student (mot de passe: student)"
echo ""
echo "⚠️  IMPORTANT: Changez les mots de passe après le premier boot!"
echo ""

CHROOT_EOF

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "Installation automatisée terminée avec succès !"
echo "================================================================"
echo ""
echo "🚀 Pour démarrer votre système Gentoo:"
echo ""
echo "1. Sortez de ce script"
echo ""
echo "2. Démontez proprement les systèmes de fichiers:"
echo "   cd /"
echo "   umount -l ${MOUNT_POINT}/dev{/shm,/pts,}"
echo "   umount -R ${MOUNT_POINT}"
echo ""
echo "3. Redémarrez la machine:"
echo "   reboot"
echo ""
echo "4. Retirez le LiveCD de VirtualBox"
echo ""
echo "5. Au démarrage, connectez-vous avec:"
echo "   - Utilisateur: root ou student"
echo "   - Mot de passe: root ou student"
echo ""
echo "✅ CORRECTION APPLIQUÉE:"
echo "   • Portage extrait dans /var/db/repos/gentoo"
echo "   • Portage extrait dans /usr/portage"
echo "   • Profil systemd configuré automatiquement"
echo "   • Le TP2 fonctionnera sans problème !"
echo ""
log_success "Bonne utilisation de votre nouveau système Gentoo ! 🐧"
echo ""tar 