#!/bin/bash
set -e

echo "=== Préparation du système ==="

# ---------------------------------------------------------
# 1. Ajout du USE flag lvm pour sys-fs/lvm2
# ---------------------------------------------------------
mkdir -p /etc/portage/package.use

echo "sys-fs/lvm2 lvm" > /etc/portage/package.use/lvm2

echo "[OK] USE flag lvm ajouté dans /etc/portage/package.use/lvm2"

emerge --ask sys-fs/lvm2

echo "[OK] lvm2 compilé avec le USE flag 'lvm'"

# ---------------------------------------------------------
# 2. Création d’une archive complète de /home
# ---------------------------------------------------------
cd /
echo "=== Création de l’archive de /home avec permissions ==="

tar czpf /root/home_backup.tar.gz /home

echo "[OK] Archive créée : /root/home_backup.tar.gz"


# ---------------------------------------------------------
# 3. Suppression de l’ancienne partition /dev/sda4
# ---------------------------------------------------------
echo "=== Démontage de /home ==="
umount /home || echo " /home était déjà démonté"

echo "=== Suppression de /dev/sda4 ==="
# L’utilisateur devra confirmer dans fdisk
fdisk /dev/sda <<EOF
d
4
w
EOF

echo "[OK] Partition /dev/sda4 supprimée"

# ---------------------------------------------------------
# 4. Re-création en partition LVM
# ---------------------------------------------------------
echo "=== Création d’une nouvelle partition /dev/sda4 en LVM ==="

fdisk /dev/sda <<EOF
n
p
4


t
4
8e
w
EOF

echo "[OK] Nouvelle partition LVM /dev/sda4 créée"

# ---------------------------------------------------------
# 5. Initialisation LVM
# ---------------------------------------------------------

pvcreate /dev/sda4
vgcreate vg_home /dev/sda4
lvcreate -n home -l 100%FREE vg_home

echo "[OK] Volume logique vg_home/home créé"

mkfs.ext4 /dev/vg_home/home

echo "[OK] Nouveau système de fichiers ext4 sur /dev/vg_home/home"


# ---------------------------------------------------------
# 6. Montage et restauration
# ---------------------------------------------------------

mount /dev/vg_home/home /home

echo "=== Restauration du contenu de /home ==="

tar xzpf /root/home_backup.tar.gz -C /

echo "[OK] Contenu restauré"


# ---------------------------------------------------------
# 7. Mise à jour du /etc/fstab
# ---------------------------------------------------------
echo "/dev/vg_home/home    /home    ext4    defaults    0 2" >> /etc/fstab

echo "[OK] /etc/fstab mis à jour"


# ---------------------------------------------------------
# 8. Préparation pour l’extension LVM (exercice 2.14)
# Le nouveau disque sera /dev/sdb
# ---------------------------------------------------------

echo "=== Préparation pour extension future (/dev/sdb) ==="
echo "Quand vous ajouterez /dev/sdb :"

cat <<EOF

  fdisk /dev/sdb
    → créer une partition de type LVM (type 8e)
  pvcreate /dev/sdb1
  vgextend vg_home /dev/sdb1
  lvextend -l +100%FREE /dev/vg_home/home
  resize2fs /dev/vg_home/home

EOF

echo "=== Script terminé avec succès ==="
