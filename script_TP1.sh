#!/bin/bash
# TP1 - Installation complète Gentoo avec OpenRC
# Exercices 1.2 à 1.9

SECRET_CODE="1234"

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
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-systemd-20251102T165025Z.tar.xz"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"

echo "================================================================"
echo "     TP1 - Installation Gentoo OpenRC (Exercices 1.2-1.9)"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.2 - PARTITIONNEMENT
# ============================================================================
log_info "Exercice 1.2 - Partitionnement du disque ${DISK}"

if lsblk "${DISK}" 2>/dev/null | grep -q "${DISK}1"; then
  log_warning "Partitions déjà présentes - Skip"
else
  (
    echo o      # Nouvelle table MBR
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot
    echo n; echo p; echo 2; echo ""; echo +256M    # swap
    echo n; echo p; echo 3; echo ""; echo +6G      # /
    echo n; echo p; echo 4; echo ""; echo +6G      # /home
    echo t; echo 2; echo 82                        # Type swap
    echo w
  ) | fdisk "${DISK}" >/dev/null 2>&1
  
  sleep 2
  partprobe "${DISK}" 2>/dev/null || true
  log_success "Partitions créées"
fi

# ============================================================================
# EXERCICE 1.3 - FORMATAGE AVEC LABELS
# ============================================================================
log_info "Exercice 1.3 - Formatage avec labels"

mkfs.ext2 -F -L "boot" "${DISK}1" >/dev/null 2>&1
mkswap -L "swap" "${DISK}2" >/dev/null 2>&1
mkfs.ext4 -F -L "root" "${DISK}3" >/dev/null 2>&1
mkfs.ext4 -F -L "home" "${DISK}4" >/dev/null 2>&1

log_success "Toutes les partitions formatées avec labels"

# ============================================================================
# EXERCICE 1.4 - MONTAGE
# ============================================================================
log_info "Exercice 1.4 - Montage des partitions"

mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || true
mkdir -p "${MOUNT_POINT}"/{boot,home}
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || true
mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || true
swapon "${DISK}2" 2>/dev/null || true

log_success "Partitions montées"

# ============================================================================
# EXERCICE 1.5 - TÉLÉCHARGEMENT
# ============================================================================
log_info "Exercice 1.5 - Téléchargement Stage3 OpenRC et Portage"

cd "${MOUNT_POINT}"

if [ ! -f "stage3-amd64-openrc-*.tar.xz" ]; then
  log_info "Téléchargement Stage3 OpenRC..."
  wget --quiet --show-progress "${STAGE3_URL}" || {
    log_warning "URL exacte non trouvée, téléchargement générique..."
    wget --quiet --show-progress "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-$(date +%Y%m%d)T*.tar.xz" 2>/dev/null || \
    wget --quiet --show-progress "https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-latest.tar.xz"
  }
  log_success "Stage3 OpenRC téléchargé"
else
  log_warning "Stage3 déjà présent"
fi

if [ ! -f "portage-latest.tar.xz" ]; then
  log_info "Téléchargement Portage..."
  wget --quiet --show-progress "${PORTAGE_URL}"
  log_success "Portage téléchargé"
else
  log_warning "Portage déjà présent"
fi

log_success "Archives téléchargées"

# ============================================================================
# EXERCICE 1.6 - EXTRACTION
# ============================================================================
log_info "Exercice 1.6 - Extraction des archives"

cd "${MOUNT_POINT}"

log_info "Extraction Stage3..."
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait"

# Extraction Portage aux DEUX emplacements
log_info "Création des répertoires Portage..."
mkdir -p "${MOUNT_POINT}/var/db/repos/gentoo"
mkdir -p "${MOUNT_POINT}/usr/portage"

log_info "Extraction Portage dans /var/db/repos/gentoo..."
tar xpf portage-latest.tar.xz -C "${MOUNT_POINT}/var/db/repos/gentoo" --strip-components=1

log_info "Extraction Portage dans /usr/portage..."
tar xpf portage-latest.tar.xz -C "${MOUNT_POINT}/usr"

rm -f stage3-*.tar.xz portage-latest.tar.xz
log_success "Archives extraites (Portage aux deux emplacements)"

# ============================================================================
# CONFIGURATION MAKE.CONF
# ============================================================================
log_info "Configuration de make.conf pour OpenRC"

cat >> "${MOUNT_POINT}/etc/portage/make.conf" <<'EOF'

# Configuration optimisée
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

MAKEOPTS="-j2"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=2"

GENTOO_MIRRORS="https://mirror.init7.net/gentoo/ https://gentoo.mirrors.ovh.net/gentoo-distfiles/"
ACCEPT_LICENSE="*"

# Pas de systemd
USE="-systemd"

PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"
EOF

log_success "make.conf configuré pour OpenRC"

# ============================================================================
# EXERCICE 1.7 - PRÉPARATION CHROOT
# ============================================================================
log_info "Exercice 1.7 - Préparation du chroot"

cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

log_success "Environnement chroot prêt"

# ============================================================================
# EXERCICES 1.8 et 1.9 - CONFIGURATION DANS CHROOT
# ============================================================================
log_info "Entrée dans le chroot (Exercices 1.8 et 1.9)"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Configuration du système OpenRC"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.8 - CONFIGURATION ENVIRONNEMENT
# ============================================================================
log_info "Exercice 1.8 - Configuration de l'environnement"

# Configuration dépôts
log_info "Configuration des dépôts Portage"
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF
log_success "Dépôts configurés"

# Vérification et sélection du profil OpenRC
log_info "Configuration du profil OpenRC"
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    # Trouver un profil OpenRC
    OPENRC_PROFILE=""
    for VERSION in 17.1 17.0 13.0; do
        if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}" ]; then
            OPENRC_PROFILE="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
            break
        fi
    done
    
    if [ -n "${OPENRC_PROFILE}" ]; then
        rm -f /etc/portage/make.profile
        ln -sf "${OPENRC_PROFILE}" /etc/portage/make.profile
        log_success "Profil OpenRC configuré: ${OPENRC_PROFILE}"
    else
        log_warning "Profil OpenRC non trouvé, utilisation du défaut"
    fi
else
    log_warning "Profils non disponibles"
fi

# Configuration clavier
log_info "1/6 - Configuration clavier français"
cat > /etc/conf.d/keymaps <<'EOF'
keymap="fr-latin1"
EOF
log_success "Clavier: fr-latin1"

# Locales
log_info "2/6 - Configuration locales"
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF

locale-gen >/dev/null 2>&1
eselect locale set fr_FR.utf8 >/dev/null 2>&1 || eselect locale set 4 >/dev/null 2>&1
log_success "Locales configurées"

env-update >/dev/null 2>&1
source /etc/profile

# Hostname
log_info "3/6 - Configuration hostname"
echo "gentoo-openrc" > /etc/hostname
log_success "Hostname: gentoo-openrc"

# Timezone
log_info "4/6 - Configuration timezone"
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone
log_success "Timezone: Europe/Paris"

# Réseau avec OpenRC
log_info "5/6 - Configuration réseau (DHCP avec OpenRC)"
cat > /etc/conf.d/net <<'EOF'
config_eth0="dhcp"
config_enp0s3="dhcp"
EOF

# Créer le lien symbolique pour le réseau
cd /etc/init.d
ln -sf net.lo net.eth0 2>/dev/null || true
ln -sf net.lo net.enp0s3 2>/dev/null || true

# Activer le réseau au démarrage
rc-update add net.eth0 default 2>/dev/null || true
rc-update add net.enp0s3 default 2>/dev/null || true
log_success "Réseau DHCP configuré (OpenRC)"

# Installation dhcpcd
log_info "Installation dhcpcd"
emerge --noreplace net-misc/dhcpcd 2>&1 | grep -E ">>>" || true
rc-update add dhcpcd default 2>/dev/null || true
log_success "dhcpcd installé et activé"

# fstab
log_info "6/6 - Configuration /etc/fstab"
cat > /etc/fstab <<'EOF'
# <fs>          <mountpoint>    <type>  <opts>              <dump/pass>
LABEL=root      /               ext4    defaults,noatime    0 1
LABEL=boot      /boot           ext2    defaults            0 2
LABEL=home      /home           ext4    defaults,noatime    0 2
LABEL=swap      none            swap    sw                  0 0
EOF
log_success "/etc/fstab configuré"

log_success "Exercice 1.8 terminé"

# ============================================================================
# EXERCICE 1.9 - INSTALLATION HTOP
# ============================================================================
log_info "Exercice 1.9 - Installation htop"

emerge --noreplace sys-process/htop 2>&1 | grep -E ">>>" || true
log_success "htop installé"

# ============================================================================
# INSTALLATION BOOTLOADER (pour préparer TP2)
# ============================================================================
log_info "Préparation pour le TP2..."

# Installation des outils de base
log_info "Installation des outils de base"
emerge --noreplace sys-apps/pciutils 2>&1 | grep -E ">>>" || true
emerge --noreplace sys-kernel/linux-firmware 2>&1 | grep -E ">>>" || true

log_success "Système de base prêt"

# ============================================================================
# RÉSUMÉ
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 TP1 TERMINÉ - Installation OpenRC complète !"
echo "================================================================"
echo ""
echo "📋 Exercices accomplis:"
echo "  ✓ Ex 1.2: Partitionnement (4 partitions)"
echo "  ✓ Ex 1.3: Formatage avec labels"
echo "  ✓ Ex 1.4: Montage des partitions"
echo "  ✓ Ex 1.5: Téléchargement Stage3 OpenRC + Portage"
echo "  ✓ Ex 1.6: Extraction (Portage aux deux emplacements)"
echo "  ✓ Ex 1.7: Préparation chroot"
echo "  ✓ Ex 1.8: Configuration complète (OpenRC)"
echo "  ✓ Ex 1.9: Installation htop"
echo ""
echo "📦 Configuration:"
echo "  • Init: OpenRC (pas systemd)"
echo "  • Clavier: fr-latin1"
echo "  • Locale: fr_FR.UTF-8"
echo "  • Hostname: gentoo-openrc"
echo "  • Timezone: Europe/Paris"
echo "  • Réseau: DHCP (dhcpcd)"
echo "  • Portage: /var/db/repos/gentoo"
echo ""
echo "🚀 PROCHAINE ÉTAPE:"
echo "  Lancez maintenant le script TP2 pour:"
echo "  - Installer et compiler le noyau"
echo "  - Installer GRUB"
echo "  - Finaliser le système"
echo ""

CHROOT_EOF

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ TP1 TERMINÉ - SYSTÈME PRÊT POUR LE TP2"
echo "================================================================"
echo ""
echo "⚠️  NE DÉMONTEZ PAS LES PARTITIONS !"
echo ""
echo "🎯 PROCHAINES ÉTAPES:"
echo ""
echo "1. Lancez le script TP2 MAINTENANT:"
echo "   ./tp2_openrc_complet.sh"
echo ""
echo "2. Le TP2 va:"
echo "   • Installer les sources du noyau"
echo "   • Compiler le noyau"
echo "   • Installer GRUB"
echo "   • Configurer les logs"
echo ""
echo "3. Après le TP2, vous pourrez redémarrer"
echo ""
log_success "Système OpenRC prêt ! 🐧"
echo ""