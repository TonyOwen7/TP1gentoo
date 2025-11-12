#!/bin/bash
# ========================================================
# Gentoo Installation Script — TP1 (Ex. 1.1 → 1.9)
# Disk: /dev/sda
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

# Boot
if mountpoint -q /mnt/gentoo/boot; then
  echo "✅ /dev/sda1 already mounted, skipping mkfs."
else
  mkfs.ext2 -L boot /dev/sda1
fi

# Swap
if swapon --show | grep -q "/dev/sda2"; then
  echo "✅ Swap already active, skipping mkswap."
else
  mkswap -L swap /dev/sda2
fi

# Root
if mountpoint -q /mnt/gentoo; then
  echo "✅ /dev/sda3 already mounted, skipping mkfs."
else
  mkfs.ext4 -L root /dev/sda3
fi

# Home
if mountpoint -q /mnt/gentoo/home; then
  echo "✅ /dev/sda4 already mounted, skipping mkfs."
else
  mkfs.ext4 -L home /dev/sda4
fi

echo "==== 📁 Ex. 1.4 — Mounting Partitions and Enabling Swap ===="

mkdir -p /mnt/gentoo

# Root
if mountpoint -q /mnt/gentoo; then
  echo "✅ /mnt/gentoo already mounted."
else
  mount /dev/sda3 /mnt/gentoo
fi

# Boot
mkdir -p /mnt/gentoo/boot
if mountpoint -q /mnt/gentoo/boot; then
  echo "✅ /mnt/gentoo/boot already mounted."
else
  mount /dev/sda1 /mnt/gentoo/boot
fi

# Home
mkdir -p /mnt/gentoo/home
if mountpoint -q /mnt/gentoo/home; then
  echo "✅ /mnt/gentoo/home already mounted."
else
  mount /dev/sda4 /mnt/gentoo/home
fi

# Swap
if swapon --show | grep -q "/dev/sda2"; then
  echo "✅ Swap already active."
else
  swapon /dev/sda2
fi

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

echo "==== 🌐 Ex. 1.5 — Downloading Stage 3 ===="

cd /mnt/gentoo
if ls stage3-amd64-systemd-*.tar.xz >/dev/null 2>&1; then
  echo "✅ Stage3 archive already exists."
else
  wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-latest.tar.xz
  wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-latest.tar.xz.asc
fi

echo "==== 📦 Ex. 1.6 — Extracting Stage 3 ===="

if [ -d /mnt/gentoo/bin ]; then
  echo "✅ Stage3 already extracted."
else
  # Vérification GPG si gpg est installé
  if command -v gpg >/dev/null 2>&1; then
    gpg --verify stage3-amd64-systemd-latest.tar.xz.asc stage3-amd64-systemd-latest.tar.xz || {
      echo "❌ Signature GPG invalide, arrêt."
      exit 1
    }
  fi
  tar xpf stage3-amd64-systemd-*.tar.xz --xattrs-include='*.*' --numeric-owner
fi

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

# Mount proc/sys/dev only if not yet mounted
if ! mountpoint -q /mnt/gentoo/proc; then
  mount -t proc /proc /mnt/gentoo/proc
fi
if ! mountpoint -q /mnt/gentoo/sys; then
  mount --rbind /sys /mnt/gentoo/sys
fi
if ! mountpoint -q /mnt/gentoo/dev; then
  mount --rbind /dev /mnt/gentoo/dev
fi

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

echo "==== 🌐 Installing DHCP client (dhcpcd) ===="
emerge --sync || true
emerge --noreplace dhcpcd || true

echo "==== 📦 Ex. 1.9 — Installing htop ===="
emerge --noreplace htop || true

echo "==== ✅ Base Gentoo configuration complete ===="
CHROOT_CMDS
