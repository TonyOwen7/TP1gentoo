#!/bin/bash
# ========================================================
# Gentoo Installation Script — Up to Configuration
# Disk: /dev/sda
# ========================================================

set -e

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

if blkid /dev/sda1 >/dev/null 2>&1 && blkid /dev/sda3 >/dev/null 2>&1; then
  echo "✅ Filesystems already formatted — skipping format step."
else
  mkfs.ext2 -L boot /dev/sda1
  mkswap -L swap /dev/sda2
  mkfs.ext4 -L root /dev/sda3
  mkfs.ext4 -L home /dev/sda4
fi

echo "==== 📁 Ex. 1.4 — Mounting Filesystems and Enabling Swap ===="

if mount | grep -q "/mnt/gentoo "; then
  echo "✅ Root already mounted."
else
  mkdir -p /mnt/gentoo
  mount /dev/sda3 /mnt/gentoo
fi

if mount | grep -q "/mnt/gentoo/boot "; then
  echo "✅ Boot already mounted."
else
  mkdir -p /mnt/gentoo/boot
  mount /dev/sda1 /mnt/gentoo/boot
fi

if mount | grep -q "/mnt/gentoo/home "; then
  echo "✅ Home already mounted."
else
  mkdir -p /mnt/gentoo/home
  mount /dev/sda4 /mnt/gentoo/home
fi

if swapon --show | grep -q /dev/sda2; then
  echo "✅ Swap already active."
else
  swapon /dev/sda2
fi

echo "==== 🌐 Ex. 1.5 — Downloading Stage 3 ===="

cd /mnt/gentoo

if [ -d "/mnt/gentoo/bin" ]; then
  echo "✅ Stage 3 already extracted — skipping download."
else
  if [ ! -f stage3-amd64-systemd-latest.tar.xz ]; then
    wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-latest.tar.xz
  fi
  echo "📦 Extracting Stage 3..."
  tar xpf stage3-amd64-systemd-latest.tar.xz --xattrs-include='*.*' --numeric-owner
fi

echo "==== 🌍 Downloading Portage Snapshot from distfiles ===="

cd /mnt/gentoo/usr

if [ -d "/mnt/gentoo/usr/portage" ]; then
  echo "✅ Portage already extracted — skipping download."
else
  wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
  echo "📦 Extracting Portage..."
  tar xpf portage-latest.tar.xz -C /mnt/gentoo/usr
fi

echo "==== ⚙️ Preparing Configuration Environment ===="

if mount | grep -q "/mnt/gentoo/proc"; then
  echo "✅ proc already mounted."
else
  mount --types proc /proc /mnt/gentoo/proc
fi

if mount | grep -q "/mnt/gentoo/sys"; then
  echo "✅ sys already mounted."
else
  mount --rbind /sys /mnt/gentoo/sys
  mount --make-rslave /mnt/gentoo/sys
fi

if mount | grep -q "/mnt/gentoo/dev"; then
  echo "✅ dev already mounted."
else
  mount --rbind /dev /mnt/gentoo/dev
  mount --make-rslave /mnt/gentoo/dev
fi

echo "==== ✅ All steps up to configuration completed ===="
echo "You can now chroot into Gentoo with:"
echo "chroot /mnt/gentoo /bin/bash"
echo "source /etc/profile"
echo "export PS1=\"(chroot) \$PS1\""
