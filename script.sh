#!/bin/sh
# Gentoo Installation Script - Exercises 1.2 to 1.6

set -e

DISK="/dev/sda"

echo "==== 1️⃣ Partitioning disk ($DISK) ===="
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext2 1MiB 101MiB       # /boot
parted -s "$DISK" mkpart primary linux-swap 101MiB 357MiB # swap (≈256MiB)
parted -s "$DISK" mkpart primary ext4 357MiB 6653MiB     # /
parted -s "$DISK" mkpart primary ext4 6653MiB 12853MiB    # /home

sync

echo "==== 2️⃣ Formatting partitions ===="
mkfs.ext2 -L boot ${DISK}1
mkswap -L swap ${DISK}2
mkfs.ext4 -L root ${DISK}3
mkfs.ext4 -L home ${DISK}4

echo "==== 3️⃣ Mounting partitions ===="
mount ${DISK}3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot,home}
mount ${DISK}1 /mnt/gentoo/boot
mount ${DISK}4 /mnt/gentoo/home
swapon ${DISK}2

echo "==== 4️⃣ Downloading stage3 archive ===="
cd /mnt/gentoo
wget -q https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd.tar.xz

echo "==== 5️⃣ Extracting stage3 ===="
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -p

echo "==== 6️⃣ Downloading and extracting Portage ===="
wget -q https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
tar xpvf portage-latest.tar.xz -C /mnt/gentoo/usr

echo "==== ✅ Done! Your Gentoo base system is ready in /mnt/gentoo ===="
echo "Next steps: configure /mnt/gentoo/etc/fstab, network, and chroot environment."
