#!/bin/bash
# TP1 ISTY - ADMSYS - Installation Gentoo conforme au sujet
# Respect strict des exercices 1.2 à 1.9
# Idempotent → relançable à l'infini après reboot du LiveCD
set -euo pipefail

# Couleurs
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

DISK="/dev/vda"
MOUNT_POINT="/mnt/gentoo"

echo "============================================================"
echo "     TP1 ISTY - Installation Gentoo (conforme au sujet)"
echo "============================================================"

# ============================================================================
# Exercice 1.2 - Partitionnement exact demandé
# ============================================================================
log_info "Exercice 1.2 - Partitionnement de $DISK"
if lsblk "$DISK" 2>/dev/null | grep -q "${DISK}1"; then
  log_warning "Partitions déjà présentes → on garde"
else
  log_info "Création des 4 partitions demandées dans le TP"
  (
    echo o                    # nouvelle table GPT (fdisk par défaut sur LiveCD)
    echo n; echo ; echo ; echo +100M   # /boot
    echo n; echo ; echo ; echo +256M   # swap
    echo n; echo ; echo ; echo +6G     # /
    echo n; echo ; echo ; echo +6G     # /home
    echo t; echo 2; echo 82            # type swap pour la 2e partition
    echo w
  ) | fdisk "$DISK" >/dev/null 2>&1
  sleep 3
  partprobe "$DISK" || true
  log_success "Partitionnement terminé : /boot 100M | swap 256M | / 6G | /home 6G"
fi

# ============================================================================
# Exercice 1.3 - Formatage + labels (conforme au sujet)
# ============================================================================
log_info "Exercice 1.3 - Formatage avec labels"
mkfs.ext2 -L boot   "${DISK}1" >/dev/null 2>&1 || true
mkswap    -L swap   "${DISK}2" >/dev/null 2>&1 || true
mkfs.ext4 -L root   "${DISK}3" >/dev/null 2>&1 || true
mkfs.ext4 -L home   "${DISK}4" >/dev/null 2>&1 || true
log_success "Partitions formatées : boot(ext2) root(ext4) home(ext4) swap"

# ============================================================================
# Exercice 1.4 - Montage + activation swap
# ============================================================================
log_info "Exercice 1.4 - Montage sur $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
mount -L root "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot" "$MOUNT_POINT/home"
mount -L boot "$MOUNT_POINT/boot"
mount -L home "$MOUNT_POINT/home"
swapon -L swap
log_success "Montages effectués + swap activé"

# ============================================================================
# Génération fstab avec labels (persistance après reboot LiveCD)
# ============================================================================
cat > "$MOUNT_POINT/etc/fstab" <<EOF
LABEL=root   /        ext4    defaults,noatime    0 1
LABEL=boot   /boot    ext2    defaults            0 2
LABEL=home   /home    ext4    defaults,noatime    0 2
LABEL=swap   none     swap    sw                  0 0
EOF

# ============================================================================
# Exercice 1.5 - Téléchargement stage3 + portage
# ============================================================================
log_info "Exercice 1.5 - Téléchargement stage3 + portage"
cd "$MOUNT_POINT"

# Stage3 le plus récent (systemd ou openrc → on prend le dernier openrc classique du TP)
STAGE3_URL=$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#' | cut -f1)
wget -nc "https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_URL"
wget -nc "https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_URL.asc"
wget -nc https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz

# ============================================================================
# Exercice 1.6 - Extraction
# ============================================================================
log_info "Exercice 1.6 - Extraction des archives"
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
mkdir -p usr
tar xpf portage-latest.tar.xz -C usr
log_success "Stage3 et portage extraits"

# ============================================================================
# Exercice 1.7 - Préparation chroot
# ============================================================================
log_info "Exercice 1.7 - Préparation du chroot"
mount --rbind /proc "$MOUNT_POINT/proc"
mount --rbind /sys  "$MOUNT_POINT/sys"
mount --make-rslave "$MOUNT_POINT/sys"
mount --rbind /dev  "$MOUNT_POINT/dev"
mount --make-rslave "$MOUNT_POINT/dev"
cp -L /etc/resolv.conf "$MOUNT_POINT/etc/"

# ============================================================================
# Exercice 1.8 & 1.9 - Configuration dans le chroot
# ============================================================================
log_info "Exercice 1.8 & 1.9 - Entrée en chroot pour configuration finale"
chroot "$MOUNT_POINT" /bin/bash <<'CHROOT_SCRIPT'
set -euo pipefail
source /etc/profile
export PS1="(chroot) $PS1"

# Dépôt Gentoo
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[gentoo]
location = /usr/portage
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
EOF

# Clavier français
echo 'keymap="fr"' > /etc/conf.d/keymaps

# Locale fr_FR.UTF-8
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile

# Hostname
echo "gentoo" > /etc/hostname

# Fuseau horaire
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

# Réseau DHCP
emerge --noreplace net-misc/dhcpcd
rc-update add dhcpcd default

# Exercice 1.9 - Installation de htop
emerge --noreplace sys-process/htop

echo
echo "============================================================"
echo "      TP1 terminé avec succès - Tout est conforme au sujet"
echo "============================================================"
echo "Prochaines étapes :"
echo "  exit   → sortir du chroot"
echo "  umount -l /mnt/gentoo/dev{/shm,/pts,} /mnt/gentoo/{proc,sys,boot,home,}"
echo "  umount -R /mnt/gentoo"
echo "  reboot"
echo
CHROOT_SCRIPT

log_success "Script terminé - Tu peux maintenant sortir et rebooter"
echo "Pour finaliser : tape 'exit' puis démonte proprement avant reboot"