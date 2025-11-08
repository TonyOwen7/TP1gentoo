#!/bin/bash
# =====================================================
# Gentoo setup script: Exercises 1.2 → Configuration
# Disk: /dev/sda
# =====================================================

set -e

echo "==== 🧩 Ex. 1.2 — Partitioning Disk ===="

if lsblk /dev/sda | grep -q sda1; then
  echo "Partitions already exist, skipping fdisk."
else
  echo "Creating new partitions..."
  (
    echo o        # New DOS table
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot
    echo n; echo p; echo 2; echo ""; echo +256M    # swap
    echo n; echo p; echo 3; echo ""; echo +6G      # /
    echo n; echo p; echo 4; echo ""; echo +6G      # /home
    echo t; echo 2; echo 82                        # mark swap
    echo w
  ) | fdisk /dev/sda
fi

echo "==== 💾 Ex. 1.3 — Formatting Partitions ===="

mkfs.ext2 -L boot /dev/sda1
mkswap -L swap /dev/sda2
mkfs.ext4 -L root /dev/sda3
mkfs.ext4 -L home /dev/sda4

echo "==== 📁 Ex. 1.4 — Mounting and Activating Swap ===="

mkdir -p /mnt/gentoo
mount /dev/sda3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot,home}
mount /dev/sda1 /mnt/gentoo/boot
mount /dev/sda4 /mnt/gentoo/home
swapon /dev/sda2

echo "==== 🌐 Ex. 1.5 — Downloading stage3 ===="
cd /mnt/gentoo

# Get latest stage3 file name from Gentoo bouncer
STAGE3_PATH=$(wget -qO- https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt | grep -v '^#' | head -n1 | awk '{print $1}')
STAGE3_URL="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_PATH}"
echo "Downloading ${STAGE3_URL}"
wget -q --show-progress "${STAGE3_URL}"

echo "==== 📦 Ex. 1.6 — Extracting stage3 ===="
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

echo "==== ⚙️ Configuration — Preparing Gentoo environment ===="

# Mount vital filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/dev

# Generate /mnt/gentoo/etc/fstab automatically
echo "Generating fstab..."
BOOT_UUID=$(blkid -s UUID -o value /dev/sda1)
SWAP_UUID=$(blkid -s UUID -o value /dev/sda2)
ROOT_UUID=$(blkid -s UUID -o value /dev/sda3)
HOME_UUID=$(blkid -s UUID -o value /dev/sda4)

cat <<EOF > /mnt/gentoo/etc/fstab
# /etc/fstab
UUID=${ROOT_UUID}   /        ext4    defaults,noatime  0 1
UUID=${BOOT_UUID}   /boot    ext2    defaults          0 2
UUID=${HOME_UUID}   /home    ext4    defaults,noatime  0 2
UUID=${SWAP_UUID}   none     swap    sw                0 0
EOF

echo "==== ✅ Base system ready ===="
echo "You can now chroot with:"
echo "  mount --types proc /proc /mnt/gentoo/proc"
echo "  mount --rbind /sys /mnt/gentoo/sys"
echo "  mount --rbind /dev /mnt/gentoo/dev"
echo "  chroot /mnt/gentoo /bin/bash"
echo "  source /etc/profile"
