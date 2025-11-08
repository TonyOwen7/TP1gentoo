#!/bin/bash
# ========================================================
# Gentoo Installation Script — Full TP 1 (1.2 → 1.9)
# Disk: /dev/sda
# ========================================================

set -e

echo "==== 🧩 Ex. 1.2 — Partitioning the Disk (/dev/sda) ===="

if lsblk /dev/sda | grep -q sda1; then
  echo "✅ Partitions already exist — skipping fdisk."
else
  echo "Creating new partitions..."
  (
    echo o          # new DOS table
    echo n; echo p; echo 1; echo ""; echo +100M
    echo n; echo p; echo 2; echo ""; echo +256M
    echo t; echo 2; echo 82
    echo n; echo p; echo 3; echo ""; echo +6G
    echo n; echo p; echo 4; echo ""; echo +6G
    echo w
  ) | fdisk /dev/sda
fi

echo "==== 💾 Ex. 1.3 — Formatting Partitions ===="

# /boot
if ! blkid -s TYPE -o value /dev/sda1 | grep -q ext2; then
  echo "Formatting /boot..."
  mkfs.ext2 -L boot /dev/sda1
fi

# swap
if ! blkid -s TYPE -o value /dev/sda2 | grep -q swap; then
  echo "Setting up swap..."
  mkswap -L swap /dev/sda2
fi

# root /
if ! blkid -s TYPE -o value /dev/sda3 | grep -q ext4; then
  echo "Formatting root /..."
  mkfs.ext4 -L root /dev/sda3
fi

# /home
if ! blkid -s TYPE -o value /dev/sda4 | grep -q ext4; then
  echo "Formatting /home..."
  mkfs.ext4 -L home /dev/sda4
fi


echo "==== 📁 Ex. 1.4 — Mounting Partitions and Enabling Swap ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot
mkdir -p /mnt/gentoo/home
mount /dev/sda4 /mnt/gentoo/home
swapon /dev/sda2 || true

echo "==== 🗂️ Generating /mnt/gentoo/etc/fstab ===="

mkdir -p /mnt/gentoo/etc
cat > /mnt/gentoo/etc/fstab <<EOF
LABEL=root   /       ext4    defaults,noatime 0 1
LABEL=boot   /boot   ext2    defaults         0 2
LABEL=home   /home   ext4    defaults,noatime 0 2
LABEL=swap   none    swap    sw               0 0
EOF

echo "✅ /etc/fstab generated."

echo "==== 🌐 Ex. 1.5 — Downloading Stage 3 ===="

cd /mnt/gentoo
if [ ! -d bin ]; then
  wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-20251102T165025Z.tar.xz
  tar xpf stage3-amd64-systemd-20251102T165025Z.tar.xz --xattrs-include='*.*' --numeric-owner
else
  echo "✅ Stage3 already extracted."
fi

echo "==== 📦 Ex. 1.6 — Downloading and Extracting Portage ===="

cd /mnt/gentoo/usr
if [ ! -d /mnt/gentoo/usr/portage ]; then
  wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
  tar xpf portage-latest.tar.xz -C /mnt/gentoo/usr
else
  echo "✅ Portage already installed."
fi

echo "==== ⚙️ Preparing Configuration Environment ===="

mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

echo "==== 🧩 Ex. 1.7 → 1.9 — Chroot & System Configuration ===="

chroot /mnt/gentoo /bin/bash <<'CHROOT_CMDS'
set -e
source /etc/profile
export PS1="(chroot) $PS1"

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

# Network (DHCP via dhcpcd)
echo 'config_eth0="dhcp"' > /etc/conf.d/net
cd /etc/init.d
ln -s net.lo net.eth0 || true
rc-update add net.eth0 default
emerge --sync || true
emerge --ask --noreplace dhcpcd || true
rc-update add dhcpcd default
/etc/init.d/dhcpcd start

echo "==== 📦 Ex. 1.9 — Installing htop ===="
emerge --ask --noreplace htop || true

echo "==== ✅ Base Gentoo configuration complete ===="
CHROOT_CMDS
