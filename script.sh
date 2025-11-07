#!/bin/sh
# ======================================================
# Gentoo Automated Installation Script (Safe & Smart)
# Skips already completed steps (idempotent)
# ======================================================

set -e

DISK="/dev/sda"

echo "==== 1️⃣ Checking existing partitions on $DISK ===="
if ! lsblk -f | grep -q "${DISK}1"; then
    echo "Creating new partitions..."
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
else
    echo "✅ Partitions already exist, skipping fdisk."
fi

echo "==== 2️⃣ Formatting partitions if needed ===="
[ -z "$(blkid ${DISK}1)" ] && mkfs.ext2 -L boot ${DISK}1 || echo "✅ ${DISK}1 already formatted"
[ -z "$(blkid ${DISK}2)" ] && mkswap -L swap ${DISK}2 || echo "✅ ${DISK}2 already has swap"
[ -z "$(blkid ${DISK}3)" ] && mkfs.ext4 -L root ${DISK}3 || echo "✅ ${DISK}3 already formatted"
[ -z "$(blkid ${DISK}4)" ] && mkfs.ext4 -L home ${DISK}4 || echo "✅ ${DISK}4 already formatted"

echo "==== 3️⃣ Mounting partitions ===="
mkdir -p /mnt/gentoo
mountpoint -q /mnt/gentoo || mount ${DISK}3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot,home}
mountpoint -q /mnt/gentoo/boot || mount ${DISK}1 /mnt/gentoo/boot
mountpoint -q /mnt/gentoo/home || mount ${DISK}4 /mnt/gentoo/home
swapon --show | grep -q "${DISK}2" || swapon ${DISK}2

echo "==== 4️⃣ Downloading Stage3 ===="
cd /mnt/gentoo
if [ ! -f stage3.tar.xz ]; then
    wget -O stage3.tar.xz "https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd.tar.xz"
else
    echo "✅ Stage3 archive already exists."
fi

echo "==== 5️⃣ Extracting Stage3 ===="
if [ ! -d /mnt/gentoo/bin ]; then
    tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner -p
else
    echo "✅ Stage3 already extracted."
fi

echo "==== 6️⃣ Downloading Portage ===="
if [ ! -f portage-latest.tar.xz ]; then
    wget -O portage-latest.tar.xz "https://bouncer.gentoo.org/fetch/root/all/snapshots/portage-latest.tar.xz"
else
    echo "✅ Portage snapshot already exists."
fi

echo "==== 7️⃣ Extracting Portage ===="
if [ ! -d /mnt/gentoo/usr/portage ]; then
    tar xpvf portage-latest.tar.xz -C /mnt/gentoo/usr
else
    echo "✅ Portage already extracted."
fi

echo "==== 8️⃣ Generating /mnt/gentoo/etc/fstab ===="
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

echo "==== 9️⃣ Preparing chroot environment ===="
mountpoint -q /mnt/gentoo/proc || mount -t proc /proc /mnt/gentoo/proc
mountpoint -q /mnt/gentoo/sys  || mount --rbind /sys /mnt/gentoo/sys
mountpoint -q /mnt/gentoo/dev  || mount --rbind /dev /mnt/gentoo/dev
cp -L /etc/resolv.conf /mnt/gentoo/etc/ 2>/dev/null || true

echo "==== 🔟 Basic Configuration ===="
cat <<EOT > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -march=native -pipe"
MAKEOPTS="-j$(nproc)"
USE="bindist"
EOT
echo "gentoo-vm" > /mnt/gentoo/etc/hostname

echo ""
echo "✅ Installation base complete!"
echo "👉 You can now chroot with:"
echo "chroot /mnt/gentoo /bin/bash"
echo "source /etc/profile"
echo "export PS1=\"(chroot) \$PS1\""
