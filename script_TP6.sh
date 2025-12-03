#!/bin/bash
# TP6 - Script pratique uniquement - VERSION FDISK

set -e

# Configuration
BACKUP_DIR="/backup"
MYSQL_USER="root"
MYSQL_PASS="adminsys"
LDAP_BASE="dc=istycorp,dc=com"
DATE=$(date +%Y%m%d_%H%M%S)

# 1. Préparation du disque (Exercice 6.6-6.7) - VERSION FDISK
echo "=== Préparation du disque de sauvegarde ==="
if [[ ! -b /dev/sdb ]]; then
    echo "ERREUR: Ajoutez d'abord un disque dur via VirtualBox/Virt-manager"
    echo "Configuration -> Stockage -> Ajouter un disque dur"
    exit 1
fi

# Créer une partition avec fdisk
echo "Création de la partition sur /dev/sdb..."
echo -e "n\np\n1\n\n\nw" | fdisk /dev/sdb

# Attendre un moment pour que le kernel détecte la nouvelle partition
sleep 2

# Formater la partition
echo "Formatage de /dev/sdb1 en ext4..."
mkfs.ext4 /dev/sdb1

# Monter le disque
mkdir -p "$BACKUP_DIR"
mount /dev/sdb1 "$BACKUP_DIR"
echo "/dev/sdb1 $BACKUP_DIR ext4 defaults 0 2" >> /etc/fstab

# 2. Création structure (Exercice 6.9)
echo "=== Création de la structure de sauvegarde ==="
mkdir -p "$BACKUP_DIR"/{full,incremental,logs}
mkdir -p "$BACKUP_DIR/full/${DATE}"/{homes,mysql,ldap,wordpress}
mkdir -p "$BACKUP_DIR/incremental/${DATE}"/{homes,mysql,ldap,wordpress}

# 3. Script de sauvegarde (Exercices 6.10, 6.12, 6.15, 6.16)
cat > /usr/local/bin/backup-tp6.sh << 'EOF'
#!/bin/bash
# Script de backup TP6

BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d_%H%M%S)
TYPE=$1
SNAPSHOT_FILE="$BACKUP_DIR/last_home_snapshot"

if [ "$TYPE" = "full" ]; then
    DIR="$BACKUP_DIR/full/${DATE}"
    mkdir -p "$DIR"/{homes,mysql,ldap,wordpress}
    
    # Backup homes (6.10)
    tar --create --gzip --preserve-permissions --same-owner \
        --file="$DIR/homes/homes_full_${DATE}.tar.gz" \
        --listed-incremental="$SNAPSHOT_FILE" \
        --directory=/ home
    
    # Backup MySQL (6.12)
    databases=$(mysql -u root -p"$MYSQL_PASS" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
    for db in $databases; do
        mysqldump -u root -p"$MYSQL_PASS" --single-transaction --routines --triggers "$db" | gzip > "$DIR/mysql/${db}_${DATE}.sql.gz"
    done
    
    # Backup LDAP (6.15)
    slapcat > "$DIR/ldap/ldap_${DATE}.ldif"
    gzip "$DIR/ldap/ldap_${DATE}.ldif"
    
    # Backup Wordpress (fichiers)
    tar -czf "$DIR/wordpress/wordpress_${DATE}.tar.gz" /var/www/wordpress 2>/dev/null || true
    
elif [ "$TYPE" = "incremental" ]; then
    DIR="$BACKUP_DIR/incremental/${DATE}"
    mkdir -p "$DIR"/{homes,mysql,ldap,wordpress}
    
    # Backup homes incrémental
    if [ -f "$SNAPSHOT_FILE" ]; then
        tar --create --gzip --preserve-permissions --same-owner \
            --file="$DIR/homes/homes_incremental_${DATE}.tar.gz" \
            --listed-incremental="$SNAPSHOT_FILE" \
            --directory=/ home
    fi
    
    # MySQL incrémental (dump complet mais plus petit)
    mysqldump -u root -p"$MYSQL_PASS" --single-transaction --no-create-info --insert-ignore wordpress | gzip > "$DIR/mysql/wordpress_incremental_${DATE}.sql.gz"
fi

# Checksums (6.16)
find "$DIR" -type f -name "*.gz" -exec sha256sum {} \; > "$DIR/checksums.txt"

echo "Backup $TYPE terminé dans $DIR"
EOF

chmod +x /usr/local/bin/backup-tp6.sh

# 4. Configuration Cron (Exercice 6.17)
echo "=== Configuration de Cron ==="
cat > /etc/cron.d/tp6-backup << EOF
# Sauvegarde complète chaque dimanche à 2h
0 2 * * 0 root /usr/local/bin/backup-tp6.sh full
# Sauvegarde incrémentale du lundi au samedi à 1h
0 1 * * 1-6 root /usr/local/bin/backup-tp6.sh incremental
# Test: Toutes les 5 minutes (à désactiver après test)
# */5 * * * * root /usr/local/bin/backup-tp6.sh incremental
EOF

# 5. Création des premiers backups (Exercice 6.18)
echo "=== Création des premiers backups ==="
/usr/local/bin/backup-tp6.sh full
sleep 60
# Simuler un changement pour l'incrémentale
touch /home/*/test_file_$(date +%s) 2>/dev/null || true
/usr/local/bin/backup-tp6.sh incremental

# 6. Script de restauration utilisateur (Exercice 6.20)
cat > /usr/local/bin/restore-user.sh << 'EOF'
#!/bin/bash
# Restaure le home d'un utilisateur

USER=$1
BACKUP_FILE=$2

if [ -z "$USER" ] || [ -z "$BACKUP_FILE" ]; then
    echo "Usage: restore-user.sh <username> <backup_file.tar.gz>"
    exit 1
fi

# Créer un dossier temporaire
TEMP_DIR="/tmp/restore_${USER}_$(date +%s)"
mkdir -p "$TEMP_DIR"

# Extraire uniquement l'utilisateur
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" "home/$USER" 2>/dev/null

if [ -d "$TEMP_DIR/home/$USER" ]; then
    # Copier sans écraser
    cp -r -n "$TEMP_DIR/home/$USER"/* "/home/$USER/" 2>/dev/null
    cp -r -n "$TEMP_DIR/home/$USER"/.[!.]* "/home/$USER/" 2>/dev/null
    echo "Restauration de $USER terminée"
    echo "Fichiers dans: $TEMP_DIR"
else
    echo "Utilisateur $USER non trouvé dans le backup"
fi
EOF

chmod +x /usr/local/bin/restore-user.sh

# 7. Configuration LVM (Exercice 6.21 - Bonus)
echo "=== Configuration LVM (Bonus) ==="
emerge -q sys-fs/lvm2
cat > /usr/local/bin/lvm-snapshot.sh << 'EOF'
#!/bin/bash
# Crée un snapshot LVM pour backup cohérent

VG=$(vgs --noheadings -o vg_name | head -n1 | tr -d ' ')
LV_HOME="/dev/${VG}/home"
SNAPSHOT_NAME="home_snapshot_$(date +%Y%m%d_%H%M%S)"

# Créer snapshot (10% de la taille originale)
lvcreate -L10%VG -s -n "$SNAPSHOT_NAME" "$LV_HOME"

# Monter en lecture seule
mkdir -p /mnt/snapshot
mount -o ro "/dev/${VG}/${SNAPSHOT_NAME}" /mnt/snapshot

# Backup depuis le snapshot
tar -czf "/backup/homes_snapshot_$(date +%Y%m%d_%H%M%S).tar.gz" -C /mnt/snapshot .

# Nettoyer
umount /mnt/snapshot
lvremove -f "/dev/${VG}/${SNAPSHOT_NAME}"
rmdir /mnt/snapshot
EOF

chmod +x /usr/local/bin/lvm-snapshot.sh

# 8. Vérification finale
echo "=== Vérification ==="
echo "Structure créée:"
tree -L 2 "$BACKUP_DIR" 2>/dev/null || ls -la "$BACKUP_DIR"
echo ""
echo "Scripts installés:"
ls -la /usr/local/bin/backup-tp6.sh /usr/local/bin/restore-user.sh /usr/local/bin/lvm-snapshot.sh
echo ""
echo "Cron configuré:"
cat /etc/cron.d/tp6-backup
echo ""
echo "=== TP6 PRATIQUE TERMINÉ ==="
echo "Commandes disponibles:"
echo "  backup-tp6.sh full           # Backup complet"
echo "  backup-tp6.sh incremental    # Backup incrémental"
echo "  restore-user.sh <user> <fichier>  # Restaurer un utilisateur"
echo "  lvm-snapshot.sh              # Snapshot LVM"