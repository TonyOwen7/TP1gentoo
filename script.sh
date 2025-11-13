#!/bin/bash
# ========================================================
# Gentoo Installation Script — TP1 (Ex. 1.1 → 1.9)
# Disk: /dev/sda
# Secure version with fixed stage3 (20251109T170053Z)
# ========================================================

set -euo pipefail

echo "==== 🧩 Ex. 1.2 — Partitioning the Disk (/dev/sda) ===="

if lsblk /dev/sda | grep -q sda1; then
  echo "✅ Partitions already exist — skipping fdisk setup."
else
  echo "Creating new partition table and partitions..."
  (
    echo o          # new DOS partition table
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot
    echo n; echo p; echo 2; echo ""; echo +256M    # swap
    echo n; echo p; echo 3; echo ""; echo +6G      # /
    echo n; echo p; echo 4; echo ""; echo +6G      # /home
    echo t; echo 2; echo 82                        # set partition 2 type to swap
    echo w
  ) | fdisk /dev/sda
fi

echo "==== 💾 Ex. 1.3 — Formatting Partitions ===="

mkfs.ext2 -L boot /dev/sda1 || true
mkswap -L swap /dev/sda2 || true
mkfs.ext4 -L root /dev/sda3 || true
mkfs.ext4 -L home /dev/sda4 || true

echo "==== 📁 Ex. 1.4 — Mounting Partitions and Enabling Swap ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot
mkdir -p /mnt/gentoo/home
mount /dev/sda4 /mnt/gentoo/home
swapon /dev/sda2

echo "==== 🗂️ Generating /mnt/gentoo/etc/fstab ===="

mkdir -p /mnt/gentoo/etc
cat > /mnt/gentoo/etc/fstab <<EOF
LABEL=root   /       ext4    defaults,noatime 0 1
LABEL=boot   /boot   ext2    defaults         0 2
LABEL=home   /home   ext4    defaults,noatime 0 2
LABEL=swap   none    swap    sw               0 0
EOF

echo "✅ /etc/fstab generated successfully:"
cat /mnt/gentoo/etc/fstab

echo "==== 🌐 Ex. 1.5 — Downloading Stage 3 (secure) ===="

cd /mnt/gentoo
if [ -f stage3-amd64-systemd-20251109T170053Z.tar.xz ]; then
  echo "✅ Stage3 archive already exists."
else
  wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz
  wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz.asc
fi

echo "==== 🔑 Importing Gentoo Release Key ===="
if [ -f /usr/share/openpgp-keys/gentoo-release.asc ]; then
  gpg --import /usr/share/openpgp-keys/gentoo-release.asc
else
  echo "❌ Gentoo release key not found locally. Install app-crypt/openpgp-keys-gentoo-release."
  exit 1
fi

echo "==== 🔍 Verifying Stage 3 signature ===="
if ! gpg --verify stage3-amd64-systemd-20251109T170053Z.tar.xz.asc stage3-amd64-systemd-20251109T170053Z.tar.xz; then
  echo "❌ Signature verification failed. Aborting installation."
  exit 1
fi

echo "==== 📦 Ex. 1.6 — Extracting Stage 3 ===="
tar xpf stage3-amd64-systemd-20251109T170053Z.tar.xz --xattrs-include='*.*' --numeric-owner

echo "==== 📦 Ex. 1.6 (suite) — Installing Portage ===="

mkdir -p /mnt/gentoo/usr
cd /mnt/gentoo/usr
if [ ! -d /mnt/gentoo/usr/portage ]; then
  wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
  tar xpf portage-latest.tar.xz -C /mnt/gentoo/usr
else
  echo "✅ Portage already present."
fi

echo "==== ⚙️ Preparing chroot environment ===="

mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

echo "==== 🧩 Ex. 1.7 — Chrooting into Gentoo Environment ===="

chroot /mnt/gentoo /bin/bash <<'CHROOT_CMDS'
source /etc/profile
export PS1="(chroot) \$PS1"

echo "==== 🏗️ Ex. 1.8 — System Configuration ===="

# Keyboard layout
echo 'keymap="fr-latin1"' > /etc/conf.d/keymaps

# Locale setup
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile

# Hostname
echo "gentoo" > /etc/hostname

# Timezone
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone

# Network (DHCP)
echo 'config_eth0="dhcp"' > /etc/conf.d/net
cd /etc/init.d
ln -sf net.lo net.eth0
rc-update add net.eth0 default

echo "==== ⚙️ Vérification du dépôt Gentoo ===="

# Vérifier que le répertoire existe
if [ ! -d /var/db/repos/gentoo ]; then
  echo "📂 Création du répertoire /var/db/repos/gentoo"
  mkdir -p /var/db/repos/gentoo
fi

# Vérifier la configuration repos.conf
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF

echo "✅ Fichier /etc/portage/repos.conf/gentoo.conf configuré correctement."

# Synchroniser le dépôt
echo "==== 🔄 Synchronisation du dépôt Gentoo ===="
emerge --sync || emerge-webrsync

echo "==== 🌐 Installing DHCP client (dhcpcd) ===="
emerge --noreplace dhcpcd || true

echo "==== 📦 Ex. 1.9 — Installing htop ===="
emerge --noreplace htop || true

echo "==== ✅ Base Gentoo configuration complete ===="
CHROOT_CMDS