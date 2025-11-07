#!/bin/bash

# Récupérer les UUID
ROOT_UUID=$(blkid -s UUID -o value /dev/sda3)
BOOT_UUID=$(blkid -s UUID -o value /dev/sda1)
HOME_UUID=$(blkid -s UUID -o value /dev/sda4)
SWAP_UUID=$(blkid -s UUID -o value /dev/sda2)

# Créer /etc/fstab avec UUID
cat << EOF > /etc/fstab
# <fs>        <mountpoint> <type>  <opts>           <dump/pass>
UUID=$ROOT_UUID     /       ext4    defaults,noatime 0 1
UUID=$BOOT_UUID     /boot   ext2    defaults         0 2
UUID=$HOME_UUID     /home   ext4    defaults,noatime 0 2
UUID=$SWAP_UUID     none    swap    sw               0 0
EOF

# Monter toutes les partitions
mount -a

# Vérifier swap
swapon -s
