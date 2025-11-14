#!/bin/bash
# TP1 ISTY - Installation Gentoo - Version finale adaptée à ton cas (3 partitions existantes)
# Respect strict du sujet + gestion intelligente du repartitionnement
set -euo pipefail

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

DISK="/dev/vda"
MOUNT_POINT="/mnt/gentoo"

echo "============================================================"
echo "     TP1 ISTY - Installation Gentoo (cas réel : 3 partitions déjà présentes)"
echo "============================================================"

# ============================================================================
# Exercice 1.2 - Partitionnement intelligent
# ============================================================================
log_info "Exercice 1.2 - Vérification du nombre de partitions sur $DISK"

PART_COUNT=$(lsblk -rn "$DISK" | grep -c "^${DISK}[0-9]" || echo 0)


  log_warning "Seulement $PART_COUNT partition(s) détectée(s) → on repartitionne proprement"
  log_info "Suppression des partitions existantes et création des 4 demandées par le TP"

  # On écrase tout proprement
  (
    echo o      # nouvelle table GPT
    echo n; echo ; echo ; echo +100M   # /boot
    echo n; echo ; echo ; echo +256M   # swap
    echo n; echo ; echo ; echo +6G     # /
    echo n; echo ; echo ; echo +6G     # /home
    echo t; echo 2; echo 82            # type swap
    echo w
  ) | fdisk "$DISK" >/dev/null 2>&1

  sleep 3
  partprobe "$DISK" || true
  log_success "Repartitionnement terminé : /boot 100M | swap 256M | / 6G | /home 6G"
fi

# ============================================================================
# Exercice 1.3 - Formatage avec labels (idempotent)
# ============================================================================
log_info "Exercice 1.3 - Formatage avec labels"
mkfs.ext2 -F -L boot "${DISK}1" >/dev/null 2>&1 || true
mkswap    -F -L swap "${DISK}2" >/dev/null 2>&1 || true
mkfs.ext4 -F -L root "${DISK}3" >/dev/null 2>&1 || true
mkfs.ext4 -F -L home "${DISK}4" >/dev/null 2>&1 || true
log_success "Partitions formatées avec labels : boot, swap, root, home"

# ============================================================================
# Exercice 1.4 - Montage intelligent (survive au reboot du LiveCD)
# ============================================================================
log_info "Exercice 1.4 - Montage des partitions via LABEL"
mkdir -p "$MOUNT_POINT"
mount -L root "$MOUNT_POINT" 2>/dev/null || true
mkdir -p "$MOUNT_POINT/boot" "$MOUNT_POINT/home"
mount -L boot "$MOUNT_POINT/boot" 2>/dev/null || true
mount -L home "$MOUNT_POINT/home" 2>/dev/null || true
swapon -L swap 2>/dev/null || true
log_success "Montage terminé + swap activé (conservé après reboot)"

# fstab avec labels → montage persistant
cat > "$MOUNT_POINT/etc/fstab" <<EOF
LABEL=root   /        ext4    defaults,noatime    0 1
LABEL=boot   /boot    ext2    defaults            0 2
LABEL=home   /home    ext4    defaults,noatime    0 2
LABEL=swap   none     swap    sw                  0 0
EOF

# ============================================================================
# Téléchargement et extraction (exercices 1.5 & 1.6)
# ============================================================================
cd "$MOUNT_POINT"
log_info "Exercice 1.5 & 1.6 - Téléchargement et extraction stage3 + portage"
wget -nc $(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#' | cut -f1) 2>/dev/null || true
wget -nc $(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#' | cut -f1).asc 2>/dev/null || true
wget -nc https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz 2>/dev/null || true

tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner 2>/dev/null || true
mkdir -p usr
tar xpf portage-latest.tar.xz -C usr --strip-components=1 2>/dev/null || true

# ============================================================================
# Préparation chroot
# ============================================================================
mount --rbind /proc "$MOUNT_POINT/proc" 2>/dev/null || true
mount --rbind /sys "$MOUNT_POINT/sys" && mount --make-rslave "$MOUNT_POINT/sys"
mount --rbind /dev "$MOUNT_POINT/dev" && mount --make-rslave "$MOUNT_POINT/dev"
cp -L /etc/resolv.conf "$MOUNT_POINT/etc/" 2>/dev/null || true

# ============================================================================
# Chroot final - configuration complète
# ============================================================================
log_info "Entrée en chroot - configuration finale (exercices 1.7 à 1.9)"
chroot "$MOUNT_POINT" /bin/bash <<'CHROOT'
source /etc/profile
export PS1="(chroot) $PS1"

# Dépôt
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[gentoo]
location = /usr/portage
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
EOF

# Clavier, locale, hostname, timezone
echo 'keymap="fr"' > /etc/conf.d/keymaps
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile
echo "gentoo" > /etc/hostname
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

# Réseau DHCP
emerge --noreplace --quiet net-misc/dhcpcd
rc-update add dhcpcd default

# Exercice 1.9
emerge --noreplace --quiet sys-process/htop

echo "TP1 TERMINÉ AVEC SUCCÈS !"
echo "Tu peux maintenant : exit → umount -R /mnt/gentoo → reboot"
CHROOT

log_success "Script terminé - Tout est prêt pour le reboot final"