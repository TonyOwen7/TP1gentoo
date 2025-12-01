#!/bin/bash
# backup-lvm-snapshot.sh - Sauvegarde avec snapshot LVM

VG_NAME="vg00"
LV_HOME="lv_home"
SNAPSHOT_NAME="home_snapshot"
SNAPSHOT_SIZE="5G"
BACKUP_DIR="/mnt/backup"
DATE=$(date +%Y%m%d_%H%M%S)

# Création du snapshot
lvcreate --snapshot --name "$SNAPSHOT_NAME" --size "$SNAPSHOT_SIZE" /dev/$VG_NAME/$LV_HOME

# Montage du snapshot
mkdir -p /mnt/snapshot
mount -o ro /dev/$VG_NAME/$SNAPSHOT_NAME /mnt/snapshot

# Sauvegarde depuis le snapshot
tar --create \
    --preserve-permissions \
    --xattrs \
    --acls \
    --gzip \
    --file="$BACKUP_DIR/homes_snapshot_$DATE.tar.gz" \
    -C /mnt/snapshot . 2>/dev/null

# Démontage et suppression du snapshot
umount /mnt/snapshot
lvremove -f /dev/$VG_NAME/$SNAPSHOT_NAME

# Vérification
if [ $? -eq 0 ]; then
    echo "Sauvegarde LVM snapshot terminée avec succès"
else
    echo "Erreur lors de la sauvegarde LVM"
fi