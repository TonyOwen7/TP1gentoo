#!/bin/bash
# Gentoo Installation Script — TP1 (Ex. 1.1 → 1.9)
# Sécurisé, robuste, et intelligent

set -euo pipefail

echo "==== 🧩 Partitionnement du disque /dev/sda ===="

if lsblk /dev/sda | grep -q sda1; then
  echo "✅ Partitions déjà présentes — skip fdisk."
else
  (
    echo o
    echo n; echo p; echo 1; echo ""; echo +100M
    echo n; echo p; echo 2; echo ""; echo +256M
    echo n; echo p; echo 3; echo ""; echo +6G
    echo n; echo p; echo 4; echo ""; echo +6G
    echo t; echo 2; echo 82
    echo w
  ) | fdisk /dev/sda
fi

echo "==== 💾 Formatage des partitions ===="

mkfs.ext2 -L boot /dev/sda1 || true
mkfs.ext4 -L root /dev/sda3 || true
mkfs.ext4 -L home /dev/sda4 || true

echo "==== 🔍 Vérification et activation du swap ===="

SWAP_DEVICE=$(blkid -L swap || true)

if [ -z "$SWAP_DEVICE" ]; then
  echo "❌ Aucun périphérique avec le label 'swap' trouvé."
  echo "🔧 Formatage de /dev/sda2 avec label 'swap'..."
  mkswap -L swap /dev/sda2
  SWAP_DEVICE="/dev/sda2"
else
  echo "✅ Périphérique swap détecté : $SWAP_DEVICE"
fi

if swapon --show | grep -q "$SWAP_DEVICE"; then
  echo "✅ Le swap est déjà activé sur $SWAP_DEVICE."
else
  echo "🔧 Activation du swap sur $SWAP_DEVICE..."
  swapon "$SWAP_DEVICE"
  echo "✅ Swap activé avec succès."
fi

echo "==== 📁 Montage des partitions ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot
mkdir -p /mnt/gentoo/home
mount /dev/sda4 /mnt/gentoo/home

echo "==== 🗂️ Création de /etc/fstab ===="

mkdir -p /mnt/gentoo/etc
cat > /mnt/gentoo/etc/fstab <<EOF
LABEL=root   /       ext4    defaults,noatime 0 1
LABEL=boot   /boot   ext2    defaults         0 2
LABEL=home   /home   ext4    defaults,noatime 0 2
LABEL=swap   none    swap    sw               0 0
EOF

echo "==== 🌐 Téléchargement du stage3 + signature ===="

cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz.asc

echo "==== 🔑 Importation de la clé Gentoo ===="

gpg --import /usr/share/openpgp-keys/gentoo-release.asc

echo "==== 🔍 Vérification GPG de l'archive ===="

gpg --verify stage3-amd64-systemd-20251109T170053Z.tar.xz.asc stage3-amd64-systemd-20251109T170053Z.tar.xz || {
  echo "❌ Signature invalide — arrêt."
  exit 1
}

echo "==== 📦 Extraction du stage3 ===="

tar xpf stage3-amd64-systemd-20251109T170053Z.tar.xz --xattrs-include='*.*' --numeric-owner

echo "==== 📦 Installation de Portage ===="

mkdir -p /mnt/gentoo/usr
cd /mnt/gentoo/usr
wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
tar xpf portage-latest.tar.xz -C /mnt/gentoo/usr

echo "==== ⚙️ Préparation du chroot ===="

mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

echo "==== 🧩 Chroot dans Gentoo ===="

chroot /mnt/gentoo /bin/bash <<'CHROOT_CMDS'
source /etc/profile
export PS1="(chroot) \$PS1"

echo "==== ⚙️ Configuration du dépôt Gentoo ===="

mkdir -p /var/db/repos/gentoo
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF

echo "==== 🔄 Synchronisation du dépôt ===="
emerge --sync || emerge-webrsync

echo "==== 🏗️ Configuration système ===="

echo 'keymap="fr-latin1"' > /etc/conf.d/keymaps
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile
echo "gentoo" > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone

echo 'config_eth0="dhcp"' > /etc/conf.d/net
cd /etc/init.d
ln -sf net.lo net.eth0
rc-update add net.eth0 default

echo "==== 🌐 Installation de dhcpcd ===="
emerge --noreplace dhcpcd || true

echo "==== 📦 Installation de htop ===="
emerge --noreplace htop || true

echo "==== ✅ Configuration de base terminée ===="
CHROOT_CMDS
