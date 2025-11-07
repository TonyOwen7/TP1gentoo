#!/bin/bash
# =========================================================
# Gentoo Installation Script — Exercises 1.2 to Configuration
# Target Disk: /dev/sda
# =========================================================

set -e

echo "==== 🧩 Exercise 1.2 — Partitioning the Disk ===="

# Check if partitions already exist
if lsblk /dev/sda | grep -q sda1; then
    echo "Partitions already exist — skipping fdisk."
else
    echo "Creating partitions on /dev/sda..."
    (
        echo o      # New DOS partition table
        echo n; echo p; echo 1; echo ""; echo +100M  # /boot
        echo n; echo p; echo 2; echo ""; echo +256M  # swap
        echo n; echo p; echo 3; echo ""; echo +6G    # root
        echo n; echo p; echo 4; echo ""; echo +6G    # home
        echo t; echo 2; echo 82                      # mark swap
        echo w
    ) | fdisk /dev/sda
    echo "Partitioning complete."
fi

echo "==== 💾 Exercise 1.3 — Formatting Partitions ===="

# Format and label
mkfs.ext2 -L boot /dev/sda1
mkswap -L swap /dev/sda2
mkfs.ext4 -L root /dev/sda3
mkfs.ext4 -L home /dev/sda4
echo "Formatting complete with labels."

echo "==== 📁 Exercise 1.4 — Mounting Partitions ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo

mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot

mkdir -p /mnt/gentoo/home
mount /dev/sda4 /mnt/gentoo/home

swapon /dev/sda2
echo "Partitions mounted and swap activated."

echo "==== 🌐 Exercise 1.5 — Downloading stage3 and portage ===="

cd /mnt/gentoo

# Stage3 URL (using Gentoo bouncer)
STAGE3_URL=$(wget -qO- https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64.txt | grep -v '^#' | head -n1 | awk '{print $1}')
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_URL}

# Portage snapshot
wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz

echo "Downloads complete."

echo "==== 📦 Exercise 1.6 — Extract Archives ===="

# Extract stage3
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

# Extract portage inside /mnt/gentoo/usr
mkdir -p /mnt/gentoo/usr
tar xpvf portage-latest.tar.xz -C /mnt/gentoo/usr

echo "Extraction complete."

echo "==== ⚙️ Configuration — fstab and basic setup ===="

# Generate /etc/fstab inside /mnt/gentoo
blkid > /tmp/blkid.txt
BOOT_UUID=$(blkid -s UUID -o value /dev/sda1)
SWAP_UUID=$(blkid -s UUID -o value /dev/sda2)
ROOT_UUID=$(blkid -s UUID -o value /dev/sda3)
HOME_UUID=$(blkid -s UUID -o value /dev/sda4)

cat <<EOF > /mnt/gentoo/etc/fstab
# /etc/fstab: static file system information.
UUID=${ROOT_UUID}   /        ext4    defaults        0 1
UUID=${BOOT_UUID}   /boot    ext2    defaults        0 2
UUID=${HOME_UUID}   /home    ext4    defaults        0 2
UUID=${SWAP_UUID}   none     swap    sw              0 0
EOF

echo "Configuration complete. Your Gentoo environment is ready under /mnt/gentoo."
echo "Next steps: chroot into Gentoo and continue configuration."
