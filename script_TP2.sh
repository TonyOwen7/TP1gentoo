#!/bin/bash
# Script : migration_home_LVM.sh
# But : Migrer /home vers LVM, restaurer les fichiers et prendre en compte le flag LLVM
# Usage : exécuter en root, vérifier que /home est monté sur /dev/sda4 et qu'un fichier LLVM existe

set -euo pipefail

# ============================================================================
# VARIABLES
# ============================================================================
HOME_PARTITION="/dev/sda4"
VG_NAME="vg_home"
LV_NAME="lv_home"
LV_SIZE="10G"            # taille initiale pour le LV
BACKUP_FILE="/root/home_backup.tar.gz"  # backup temporaire
PACKAGE_USE_FILE="/etc/portage/package.use/llvm"

# ============================================================================
# Vérifications préalables
# ============================================================================
if ! command -v pvcreate >/dev/null 2>&1; then
    echo "⚠️  LVM tools non installées (pvcreate manquant). Installez lvm2."
    exit 1
fi

if [ ! -f "$PACKAGE_USE_FILE" ]; then
    echo "⚠️  Le fichier /etc/portage/package.use pour LLVM n'existe pas, création..."
    mkdir -p /etc/portage/package.use
    echo "dev-lang/llvm llvm_targets_x86" > "$PACKAGE_USE_FILE"
fi

# ============================================================================
# 1. Sauvegarde de /home
# ============================================================================
echo "📦 Sauvegarde de /home vers $BACKUP_FILE..."
tar czpf "$BACKUP_FILE" /home
echo "✅ Sauvegarde terminée."

# ============================================================================
# 2. Démonter /home
# ============================================================================
echo "🔌 Démonter /home..."
umount /home || { echo "⚠️ /home n'était pas monté"; }

# ============================================================================
# 3. Créer PV, VG et LV pour /home
# ============================================================================
echo "💿 Création du Physical Volume..."
pvcreate "$HOME_PARTITION"

echo "🗃 Création du Volume Group $VG_NAME..."
vgcreate "$VG_NAME" "$HOME_PARTITION"

echo "📁 Création du Logical Volume $LV_NAME..."
lvcreate -L "$LV_SIZE" -n "$LV_NAME" "$VG_NAME"

echo "✅ LV créé : /dev/$VG_NAME/$LV_NAME"

# ============================================================================
# 4. Formater le LV en ext4
# ============================================================================
echo "🖋 Formatage en ext4..."
mkfs.ext4 /dev/$VG_NAME/$LV_NAME

# ============================================================================
# 5. Monter le LV et restaurer les fichiers
# ============================================================================
echo "📌 Montage du LV sur /home..."
mount /dev/$VG_NAME/$LV_NAME /home

echo "📂 Restauration des fichiers depuis la sauvegarde..."
tar xzpf "$BACKUP_FILE" -C /

# ============================================================================
# 6. Mise à jour de /etc/fstab
# ============================================================================
echo "📝 Mise à jour de /etc/fstab..."
grep -q "$LV_NAME" /etc/fstab || \
echo "/dev/$VG_NAME/$LV_NAME /home ext4 defaults,noatime 0 2" >> /etc/fstab

# ============================================================================
# 7. Vérification
# ============================================================================
echo "🔍 Vérification du montage et des droits..."
mount | grep /home
ls -ld /home

echo "🎉 Migration de /home vers LVM terminée !"
echo "N'oubliez pas de vérifier le backup : $BACKUP_FILE"
echo "Le flag LLVM est actif dans : $PACKAGE_USE_FILE"
