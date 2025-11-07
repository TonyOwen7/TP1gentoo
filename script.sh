#!/bin/sh
# ======================================================
# Gentoo Automated Installation Script
# (with bouncer.gentoo.org for latest stage3 + portage)
# ======================================================

set -e

DISK="/dev/sda"

echo "==== 1️⃣ Partitioning $DISK using fdisk ===="
fdisk "$DISK" << EOF
o
n
p
1

+100M
n
p
2

+256M
t
2
82
n
p
3

+6G
n
p
4


w
EOF

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

echo "==== 4️⃣ Downloading Stage3 via BOUNCER ===="
cd /mnt/gentoo
wget -O stage3.tar.xz "https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd.tar.xz"

echo "==== 5️⃣ Extracting Stage3 ===="
tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner -p

echo "==== 6️⃣ Downloading and extracting Portage (via BOUNCER) ===="
wget -O portage-latest.tar.xz "https://bouncer.gentoo.org/fetch/root/all/snapshots/portage-latest.tar.xz"
tar xpvf portage-latest.tar.xz -C /mnt/gentoo/usr

echo "==== 7️⃣ Creating /mnt/gentoo/etc/fstab ===="
mkdir -p /mnt/gentoo/etc
> /mnt/gentoo/etc/fstab

blkid | grep "${DISK}" | while read -r line; do
    UUID=$(echo "$line" | grep -o 'UUID=\"[^\"]*\"' | cut -d'"' -f2)
    PART=$(echo "$line" | awk '{print $1}' | tr -d ':')
    case "$PART" in
        ${DISK}1) MOUNTPOINT="/boot"; FSTYPE="ext2";;
        ${DISK}2) MOUNTPOINT="none"; FSTYPE="swap";;
        ${DISK}3) MOUNTPOINT="/"; FSTYPE="ext4";;
        ${DISK}4) MOUNTPOINT="/home"; FSTYPE="ext4";;
    esac
    if [ "$FSTYPE" = "swap" ]; then
        echo "UUID=$UUID none swap sw 0 0" >> /mnt/gentoo/etc/fstab
    else
        echo "UUID=$UUID $MOUNTPOINT $FSTYPE defaults 0 1" >> /mnt/gentoo/etc/fstab
    fi
done

echo "==== 8️⃣ Preparing chroot environment ===="
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
cp -L /etc/resolv.conf /mnt/gentoo/etc/

echo "==== 9️⃣ Basic configuration ===="
cat <<EOT > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -march=native -pipe"
MAKEOPTS="-j$(nproc)"
USE="bindist"
EOT

echo "gentoo-vm" > /mnt/gentoo/etc/hostname

echo "==== 🔟 Chroot ready ===="
echo "✅ Base Gentoo environment installed with bouncer!"
echo ""
echo "👉 Enter your new system with:"
echo "chroot /mnt/gentoo /bin/bash"
echo "source /etc/profile"
echo "export PS1=\"(chroot) \$PS1\""
