#!/bin/bash
# ============================================
# Gentoo Install Script (Exercises 1.2 → 1.5)
# Disk: /dev/sda
# ============================================

set -e

echo "==== 🧩 Ex. 1.2 — Partition the disk ===="

if lsblk /dev/sda | grep -q sda1; then
  echo "Partitions already exist — skipping fdisk."
else
  echo "Creating partitions on /dev/sda..."
  (
    echo o          # new DOS table
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot
    echo n; echo p; echo 2; echo ""; echo +256M    # swap
    echo n; echo p; echo 3; echo ""; echo +6G      # /
    echo n; echo p; echo 4; echo ""; echo +6G      # /home
    echo t; echo 2; echo 82                        # swap type
    echo w
  ) | fdisk /dev/sda
fi

echo "==== 💾 Ex. 1.3 — Formatting partitions ===="

mkfs.ext2 -L boot /dev/sda1
mkswap -L swap /dev/sda2
mkfs.ext4 -L root /dev/sda3
mkfs.ext4 -L home /dev/sda4

echo "==== 📁 Ex. 1.4 — Mounting and enabling swap ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot,home}
mount /dev/sda1 /mnt/gentoo/boot
mount /dev/sda4 /mnt/gentoo/home
swapon /dev/sda2

echo "==== 🌐 Ex. 1.5 — Downloading Stage 3 ===="

cd /mnt/gentoo

# Fetch the latest stage3 file path from the Gentoo mirror list
STAGE3_PATH=$(wget -qO- https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt | grep -v '^#' | head -n1 | awk '{print $1}')

STAGE3_URL="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_PATH}"

echo "Downloading ${STAGE3_URL} ..."
wget "${STAGE3_URL}"

echo "==== ✅ Stage 3 downloaded successfully ===="
echo "File saved in /mnt/gentoo/"
