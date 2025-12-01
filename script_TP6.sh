#!/bin/bash
# TP6 - Script complet de sauvegarde/restauration
# Exécute toutes les étapes pratiques du TP

set -e  # Arrêter en cas d'erreur

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
BACKUP_ROOT="/mnt/backup"
MYSQL_USER="backup_user"
MYSQL_PASS="backup_password"
LDAP_ADMIN="cn=admin,dc=isty,dc=com"
LDAP_PASS="admin_password"
WORDPRESS_DIR="/var/www/wordpress"
LOG_FILE="/var/log/tp6_execution.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -------------------------------------------------------------------
# FONCTIONS UTILITAIRES
# -------------------------------------------------------------------
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}➤ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Ce script doit être exécuté en tant que root (sudo $0)"
    fi
}

# -------------------------------------------------------------------
# EXERCICE 6.6-6.7 : CONFIGURATION DU DISQUE
# -------------------------------------------------------------------
exercice_6_6_7() {
    log "=== EXERCICE 6.6-6.7 : CONFIGURATION DU DISQUE DE BACKUP ==="
    
    info "1. Vérification des disques disponibles..."
    echo "Disques actuels :"
    lsblk
    
    echo ""
    info "2. Ajout d'un disque dur de 20GB dans VirtualBox..."
    echo "Dans VirtualBox :"
    echo "  - Arrêter la VM"
    echo "  - Paramètres → Stockage → Contrôleur SATA → Ajouter un disque dur"
    echo "  - Créer un nouveau disque (20GB, VDI, allocation dynamique)"
    echo "  - Redémarrer la VM"
    read -p "Appuyez sur Entrée une fois le disque ajouté..."
    
    info "3. Détection du nouveau disque..."
    NEW_DISK=""
    for disk in /dev/sd[b-z]; do
        if [ -b "$disk" ] && ! lsblk "$disk" | grep -q "part"; then
            NEW_DISK="$disk"
            break
        fi
    done
    
    if [ -z "$NEW_DISK" ]; then
        warning "Aucun nouveau disque détecté. Continuer avec /dev/sdb..."
        NEW_DISK="/dev/sdb"
    fi
    
    info "4. Partitionnement de $NEW_DISK..."
    echo "Création d'une partition unique..."
    echo -e "n\np\n1\n\n\nw" | fdisk "$NEW_DISK"
    sleep 2
    
    info "5. Formatage en ext4..."
    PARTITION="${NEW_DISK}1"
    mkfs.ext4 -L "BACKUP_TP6" "$PARTITION"
    
    info "6. Configuration du montage..."
    mkdir -p "$BACKUP_ROOT"
    echo "LABEL=BACKUP_TP6 $BACKUP_ROOT ext4 defaults,noatime 0 2" >> /etc/fstab
    
    info "7. Montage du disque..."
    mount "$BACKUP_ROOT"
    
    info "8. Vérification..."
    df -h "$BACKUP_ROOT"
    
    success "Disque de backup configuré avec succès !"
}

# -------------------------------------------------------------------
# EXERCICE 6.8 : CRITIQUE (AFFICHAGE SEULEMENT)
# -------------------------------------------------------------------
exercice_6_8() {
    log "=== EXERCICE 6.8 : CRITIQUE DE LA MÉTHODE ==="
    
    echo ""
    echo "CRITIQUE DU STOCKAGE SUR DISQUE LOCAL :"
    echo "========================================"
    echo ""
    echo "AVANTAGES :"
    echo "  • Installation simple et rapide"
    echo "  • Bonnes performances (accès direct)"
    echo "  • Coût modéré"
    echo "  • Pas de dépendance réseau"
    echo ""
    echo "INCONVÉNIENTS :"
    echo "  • Pas de protection contre les sinistres locaux (incendie, vol)"
    echo "  • Vulnérable aux pannes matérielles du serveur"
    echo "  • Nécessite une sauvegarde hors site supplémentaire"
    echo "  • Évolutivité limitée"
    echo ""
    echo "AMÉLIORATIONS POSSIBLES :"
    echo "  • Ajouter une réplication sur un second disque"
    echo "  • Mettre en place une copie sur bande ou cloud"
    echo "  • Implémenter un RAID pour la redondance"
    echo ""
}

# -------------------------------------------------------------------
# EXERCICE 6.9 : ORGANISATION DES BACKUPS
# -------------------------------------------------------------------
exercice_6_9() {
    log "=== EXERCICE 6.9 : ORGANISATION DES FICHIERS ==="
    
    info "Création de la structure de sauvegarde..."
    
    # Structure principale
    mkdir -p "$BACKUP_ROOT"/{full,incremental,differential,archive,temp}
    
    # Exemple avec date
    mkdir -p "$BACKUP_ROOT/full_$DATE"/{homes,mysql,ldap,wordpress,system,logs,checksums}
    mkdir -p "$BACKUP_ROOT/incr_$DATE"/{homes,mysql,ldap,wordpress}
    
    # Fichier de métadonnées
    cat > "$BACKUP_ROOT/full_$DATE/info.txt" << EOF
Type: full
Date: $DATE
Serveur: $(hostname)
Contenu: homes, mysql, ldap, wordpress
EOF
    
    echo ""
    echo "STRUCTURE CRÉÉE :"
    echo "----------------"
    tree -L 2 "$BACKUP_ROOT" | head -20
    
    success "Structure d'organisation créée !"
}

# -------------------------------------------------------------------
# EXERCICE 6.10 : BACKUP DES HOMES
# -------------------------------------------------------------------
backup_homes() {
    local backup_type=$1
    local backup_path=$2
    
    log "Backup homes ($backup_type) vers $backup_path"
    
    SNAPSHOT_FILE="$BACKUP_ROOT/homes_snapshot.sn"
    
    case $backup_type in
        full)
            info "Sauvegarde COMPLÈTE des homes..."
            tar --create \
                --preserve-permissions \
                --xattrs \
                --acls \
                --selinux \
                --numeric-owner \
                --listed-incremental="$SNAPSHOT_FILE" \
                --gzip \
                --file="$backup_path/homes/homes_full_$DATE.tar.gz" \
                --directory="/home" .
            ;;
        incremental)
            info "Sauvegarde INCRÉMENTALE des homes..."
            if [ ! -f "$SNAPSHOT_FILE" ]; then
                warning "Pas de snapshot trouvé, création d'un backup complet..."
                backup_homes "full" "$backup_path"
                return
            fi
            
            tar --create \
                --preserve-permissions \
                --xattrs \
                --acls \
                --selinux \
                --numeric-owner \
                --listed-incremental="$SNAPSHOT_FILE" \
                --gzip \
                --file="$backup_path/homes/homes_incr_$DATE.tar.gz" \
                --directory="/home" .
            ;;
    esac
    
    # Vérification
    if tar -tzf "$backup_path/homes/"*.tar.gz >/dev/null 2>&1; then
        success "Archive homes vérifiée ($(du -h $backup_path/homes/*.tar.gz | cut -f1))"
    else
        error "Archive homes corrompue !"
    fi
}

# -------------------------------------------------------------------
# EXERCICE 6.12 : BACKUP MYSQL
# -------------------------------------------------------------------
backup_mysql() {
    local backup_path=$1
    
    log "Backup MySQL vers $backup_path"
    
    info "Création de l'utilisateur de backup si nécessaire..."
    mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASS';" 2>/dev/null || true
    mysql -e "GRANT SELECT, SHOW VIEW, RELOAD, REPLICATION CLIENT, EVENT, TRIGGER ON *.* TO '$MYSQL_USER'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    info "Sauvegarde de toutes les bases..."
    mysqldump --all-databases \
              --user="$MYSQL_USER" \
              --password="$MYSQL_PASS" \
              --single-transaction \
              --routines \
              --triggers \
              --events \
              --hex-blob | gzip > "$backup_path/mysql/all_databases_$DATE.sql.gz"
    
    # Sauvegarde individuelle de chaque base
    databases=$(mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)") || true
    
    for db in $databases; do
        info "  - Sauvegarde de la base: $db"
        mysqldump --user="$MYSQL_USER" \
                  --password="$MYSQL_PASS" \
                  --single-transaction \
                  --routines \
                  --triggers \
                  --events \
                  "$db" | gzip > "$backup_path/mysql/${db}_$DATE.sql.gz" 2>/dev/null || warning "Échec pour $db"
    done
    
    success "Sauvegarde MySQL terminée"
}

# -------------------------------------------------------------------
# EXERCICE 6.15 : BACKUP LDAP
# -------------------------------------------------------------------
backup_ldap() {
    local backup_path=$1
    
    log "Backup LDAP vers $backup_path"
    
    info "Arrêt temporaire du service LDAP..."
    /etc/init.d/slapd stop 2>/dev/null || true
    
    info "Sauvegarde avec slapcat..."
    slapcat -v -l "$backup_path/ldap/ldap_full_$DATE.ldif" 2>/dev/null || {
        warning "slapcat a échoué, tentative avec ldapsearch..."
        ldapsearch -x -H ldap://localhost -b "dc=isty,dc=com" -D "$LDAP_ADMIN" -w "$LDAP_PASS" > "$backup_path/ldap/ldap_full_$DATE.ldif" 2>/dev/null || true
    }
    
    info "Compression..."
    gzip "$backup_path/ldap/ldap_full_$DATE.ldif" 2>/dev/null || true
    
    info "Redémarrage LDAP..."
    /etc/init.d/slapd start 2>/dev/null || true
    
    # Sauvegarde configuration
    if [ -d "/etc/openldap" ]; then
        tar -czf "$backup_path/ldap/ldap_config_$DATE.tar.gz" -C /etc openldap 2>/dev/null || true
    fi
    
    success "Sauvegarde LDAP terminée"
}

# -------------------------------------------------------------------
# EXERCICE 6.16 : CHECKSUMS
# -------------------------------------------------------------------
generate_checksums() {
    local backup_path=$1
    
    log "Génération des checksums pour $backup_path"
    
    info "Création des checksums SHA256..."
    find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
        -exec sha256sum {} \; > "$backup_path/checksums/checksums_$DATE.sha256" 2>/dev/null || true
    
    info "Vérification..."
    if [ -f "$backup_path/checksums/checksums_$DATE.sha256" ]; then
        if sha256sum -c "$backup_path/checksums/checksums_$DATE.sha256" >/dev/null 2>&1; then
            success "Checksums vérifiés avec succès"
        else
            warning "Certains checksums ne correspondent pas"
        fi
    fi
}

# -------------------------------------------------------------------
# EXERCICE 6.17 : CONFIGURATION CRON
# -------------------------------------------------------------------
exercice_6_17() {
    log "=== EXERCICE 6.17 : CONFIGURATION CRON ==="
    
    # Création du script de backup
    info "Création du script de backup..."
    cat > /usr/local/bin/backup_tp6.sh << 'EOF'
#!/bin/bash
# Script de backup TP6 - Appelé par cron

BACKUP_ROOT="/mnt/backup"
LOG_FILE="/var/log/backup_tp6.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Déterminer le type de backup
DAY_OF_WEEK=$(date +%u)  # 1=Lundi, 7=Dimanche
DAY_OF_MONTH=$(date +%d)

if [ "$DAY_OF_WEEK" -eq 7 ]; then
    TYPE="full"
    BACKUP_PATH="$BACKUP_ROOT/full_$DATE"
elif [ "$DAY_OF_MONTH" -eq 1 ]; then
    TYPE="differential"
    BACKUP_PATH="$BACKUP_ROOT/diff_$DATE"
else
    TYPE="incremental"
    BACKUP_PATH="$BACKUP_ROOT/incr_$DATE"
fi

# Créer la structure
mkdir -p "$BACKUP_PATH"/{homes,mysql,ldap,wordpress,logs,checksums}

echo "$(date) - Début backup $TYPE" >> "$LOG_FILE"

# Backup homes
SNAPSHOT="$BACKUP_ROOT/homes_snapshot.sn"
if [ "$TYPE" = "full" ]; then
    tar --create --preserve-permissions --xattrs --acls --selinux \
        --listed-incremental="$SNAPSHOT" \
        --gzip --file="$BACKUP_PATH/homes/homes_$TYPE.tar.gz" \
        --directory=/home . 2>> "$BACKUP_PATH/logs/homes.log"
else
    tar --create --preserve-permissions --xattrs --acls --selinux \
        --listed-incremental="$SNAPSHOT" \
        --gzip --file="$BACKUP_PATH/homes/homes_$TYPE.tar.gz" \
        --directory=/home . 2>> "$BACKUP_PATH/logs/homes.log"
fi

# Backup MySQL
mysqldump --all-databases --user=backup_user --password=backup_password \
    --single-transaction --routines --triggers --events | \
    gzip > "$BACKUP_PATH/mysql/all_databases.sql.gz" 2>> "$BACKUP_PATH/logs/mysql.log"

# Backup LDAP
slapcat -v -l "$BACKUP_PATH/ldap/ldap_backup.ldif" 2>> "$BACKUP_PATH/logs/ldap.log"
gzip "$BACKUP_PATH/ldap/ldap_backup.ldif"

# Checksums
find "$BACKUP_PATH" -type f \( -name "*.gz" -o -name "*.tar" \) \
    -exec sha256sum {} \; > "$BACKUP_PATH/checksums/checksums.sha256" 2>> "$BACKUP_PATH/logs/checksums.log"

echo "$(date) - Backup $TYPE terminé" >> "$LOG_FILE"
EOF
    
    chmod +x /usr/local/bin/backup_tp6.sh
    
    # Configuration cron pour tests (toutes les 2 minutes)
    info "Configuration cron de test (toutes les 2 minutes)..."
    cat > /etc/cron.d/tp6-backup-test << EOF
# Test TP6 - Exécution toutes les 2 minutes
*/2 * * * * root /usr/local/bin/backup_tp6.sh

# En production :
# 0 2 * * 0 root /usr/local/bin/backup_tp6.sh   # Dimanche 2h - Full
# 0 2 * * 1-6 root /usr/local/bin/backup_tp6.sh # Lundi-Samedi 2h - Incr
# 0 3 1 * * root /usr/local/bin/backup_tp6.sh   # 1er du mois 3h - Diff
EOF
    
    chmod 644 /etc/cron.d/tp6-backup-test
    
    # Redémarrer cron
    /etc/init.d/cronie restart 2>/dev/null || systemctl restart cron 2>/dev/null || true
    
    echo ""
    echo "CRON CONFIGURÉ :"
    echo "---------------"
    cat /etc/cron.d/tp6-backup-test
    
    success "Configuration cron terminée !"
    info "Les backups s'exécuteront toutes les 2 minutes pour les tests"
}

# -------------------------------------------------------------------
# EXERCICE 6.18 : GÉNÉRATION DE BACKUPS TEST
# -------------------------------------------------------------------
exercice_6_18() {
    log "=== EXERCICE 6.18 : GÉNÉRATION DE BACKUPS TEST ==="
    
    info "1. Création d'un backup COMPLET..."
    BACKUP_FULL="$BACKUP_ROOT/full_test_$DATE"
    mkdir -p "$BACKUP_FULL"/{homes,mysql,ldap,wordpress,logs,checksums}
    
    backup_homes "full" "$BACKUP_FULL"
    backup_mysql "$BACKUP_FULL"
    backup_ldap "$BACKUP_FULL"
    generate_checksums "$BACKUP_FULL"
    
    info "2. Création d'un fichier test pour l'incrémentale..."
    echo "Fichier de test pour backup incrémental" > /home/test_file_$DATE.txt
    
    sleep 60  # Attendre 1 minute pour avoir un timestamp différent
    
    info "3. Création d'un backup INCRÉMENTAL..."
    DATE_INCR=$(date +%Y%m%d_%H%M%S)
    BACKUP_INCR="$BACKUP_ROOT/incr_test_$DATE_INCR"
    mkdir -p "$BACKUP_INCR"/{homes,mysql,ldap,wordpress}
    
    backup_homes "incremental" "$BACKUP_INCR"
    
    # Nettoyer le fichier test
    rm -f /home/test_file_*.txt
    
    echo ""
    echo "BACKUPS CRÉÉS :"
    echo "--------------"
    ls -la "$BACKUP_ROOT"/full_test_* "$BACKUP_ROOT"/incr_test_* 2>/dev/null | head -10
    
    success "Backups test générés avec succès !"
}

# -------------------------------------------------------------------
# EXERCICE 6.19-6.20 : RESTAURATION
# -------------------------------------------------------------------
exercice_6_19_20() {
    log "=== EXERCICES 6.19-6.20 : RESTAURATION ==="
    
    # Création du script de restauration
    info "Création du script de restauration..."
    cat > /usr/local/bin/restore_tp6.sh << 'EOF'
#!/bin/bash
# Script de restauration TP6

BACKUP_ROOT="/mnt/backup"
RESTORE_LOG="/var/log/restore_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "$(date) - $1" | tee -a "$RESTORE_LOG"
}

show_menu() {
    echo "=== RESTAURATION TP6 ==="
    echo "1. Restaurer un backup complet"
    echo "2. Restaurer un utilisateur spécifique (Exercice 6.20)"
    echo "3. Lister les backups disponibles"
    echo "4. Quitter"
    echo ""
    read -p "Choix [1-4]: " choice
    
    case $choice in
        1) restore_complete ;;
        2) restore_user ;;
        3) list_backups ;;
        4) exit 0 ;;
        *) echo "Choix invalide"; show_menu ;;
    esac
}

list_backups() {
    echo ""
    echo "BACKUPS DISPONIBLES:"
    echo "-------------------"
    find "$BACKUP_ROOT" -type d -name "*full*" -o -name "*incr*" -o -name "*diff*" 2>/dev/null | sort | while read dir; do
        if [ -d "$dir" ]; then
            size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            echo "$(basename "$dir") - $size"
        fi
    done
    echo ""
}

restore_complete() {
    list_backups
    read -p "Nom du backup à restaurer (ex: full_test_20240115_020000): " backup_name
    
    BACKUP_PATH="$BACKUP_ROOT/$backup_name"
    
    if [ ! -d "$BACKUP_PATH" ]; then
        echo "Backup non trouvé!"
        return 1
    fi
    
    log "Restauration depuis: $backup_name"
    
    # Vérifier les checksums
    if [ -f "$BACKUP_PATH/checksums/checksums_"*.sha256 ]; then
        echo "Vérification des checksums..."
        if ! sha256sum -c "$BACKUP_PATH/checksums/checksums_"*.sha256 >/dev/null 2>&1; then
            echo "ATTENTION: Certains fichiers sont corrompus!"
            read -p "Continuer malgré tout? (o/N): " confirm
            [[ "$confirm" != "o" && "$confirm" != "O" ]] && return 1
        fi
    fi
    
    # Restaurer homes
    if ls "$BACKUP_PATH/homes/"*.tar.gz 1>/dev/null 2>&1; then
        echo "Restauration des homes..."
        tar -xzf "$BACKUP_PATH/homes/"*.tar.gz -C /
    fi
    
    # Restaurer MySQL
    if [ -f "$BACKUP_PATH/mysql/all_databases_"*.sql.gz ]; then
        echo "Restauration MySQL..."
        gunzip -c "$BACKUP_PATH/mysql/all_databases_"*.sql.gz | mysql
    fi
    
    # Restaurer LDAP
    if ls "$BACKUP_PATH/ldap/ldap_"*.ldif.gz 1>/dev/null 2>&1; then
        echo "Restauration LDAP..."
        systemctl stop slapd 2>/dev/null || /etc/init.d/slapd stop 2>/dev/null
        gunzip -c "$BACKUP_PATH/ldap/ldap_"*.ldif.gz | slapadd
        systemctl start slapd 2>/dev/null || /etc/init.d/slapd start 2>/dev/null
    fi
    
    log "Restauration terminée"
    echo "✅ Restauration complète réussie!"
}

restore_user() {
    echo ""
    echo "=== RESTAURATION UTILISATEUR (Exercice 6.20) ==="
    echo ""
    
    read -p "Nom de l'utilisateur (ex: raj): " username
    
    # Vérifier si l'utilisateur existe
    if ! id "$username" >/dev/null 2>&1; then
        echo "L'utilisateur $username n'existe pas."
        read -p "Créer l'utilisateur? (o/N): " create_user
        if [[ "$create_user" == "o" || "$create_user" == "O" ]]; then
            useradd -m "$username"
            echo "Utilisateur $username créé."
        else
            return 1
        fi
    fi
    
    list_backups
    
    read -p "Nom du backup contenant l'utilisateur: " backup_name
    BACKUP_PATH="$BACKUP_ROOT/$backup_name"
    
    HOME_BACKUP=$(find "$BACKUP_PATH/homes" -name "*.tar.gz" 2>/dev/null | head -1)
    
    if [ ! -f "$HOME_BACKUP" ]; then
        echo "Aucune sauvegarde de homes trouvée!"
        return 1
    fi
    
    # Vérifier si l'utilisateur est dans la sauvegarde
    if ! tar -tzf "$HOME_BACKUP" | grep -q "^home/$username/"; then
        echo "L'utilisateur $username n'est pas dans cette sauvegarde."
        return 1
    fi
    
    echo "Utilisateur trouvé dans la sauvegarde."
    
    # Sauvegarde des fichiers actuels
    if [ -d "/home/$username" ]; then
        BACKUP_CURRENT="/home/${username}_backup_$(date +%Y%m%d_%H%M%S)"
        echo "Sauvegarde des fichiers actuels vers: $BACKUP_CURRENT"
        cp -r "/home/$username" "$BACKUP_CURRENT"
    fi
    
    # Extraire seulement cet utilisateur
    echo "Restauration de $username..."
    tar -xzf "$HOME_BACKUP" -C / "home/$username"
    
    # Vérifier le dossier htop-dev
    if [ -d "/home/$username/htop-dev" ]; then
        echo ""
        echo "✅ Dossier 'htop-dev' restauré avec succès!"
        echo "Contenu restauré:"
        ls -la "/home/$username/htop-dev/"
    else
        echo ""
        echo "⚠ Le dossier 'htop-dev' n'a pas été trouvé dans la sauvegarde"
    fi
    
    log "Restauration de $username terminée"
}

# Exécution
if [ $# -eq 0 ]; then
    show_menu
else
    case $1 in
        "--complete") restore_complete ;;
        "--user") restore_user ;;
        "--list") list_backups ;;
        *) show_menu ;;
    esac
fi
EOF
    
    chmod +x /usr/local/bin/restore_tp6.sh
    
    echo ""
    echo "SCRIPT DE RESTAURATION CRÉÉ :"
    echo "---------------------------"
    echo "/usr/local/bin/restore_tp6.sh"
    echo ""
    echo "UTILISATION :"
    echo "  restore_tp6.sh                    # Menu interactif"
    echo "  restore_tp6.sh --complete         # Restauration complète"
    echo "  restore_tp6.sh --user             # Restauration utilisateur"
    echo "  restore_tp6.sh --list             # Lister les backups"
    
    success "Script de restauration créé !"
}

# -------------------------------------------------------------------
# EXERCICE 6.21 : LVM SNAPSHOTS (BONUS)
# -------------------------------------------------------------------
exercice_6_21() {
    log "=== EXERCICE 6.21 : LVM SNAPSHOTS (BONUS) ==="
    
    info "Installation de LVM si nécessaire..."
    if ! command -v lvcreate >/dev/null 2>&1; then
        echo "Installation de LVM2..."
        emerge -av sys-fs/lvm2 2>/dev/null || apt-get install lvm2 -y 2>/dev/null || yum install lvm2 -y 2>/dev/null
    fi
    
    # Création du script LVM
    info "Création du script de snapshot LVM..."
    cat > /usr/local/bin/backup_lvm.sh << 'EOF'
#!/bin/bash
# Backup avec snapshots LVM

VG_NAME="vg00"  # Ajuster selon votre configuration
LV_HOME="lv_home"  # Ajuster selon votre configuration

# Vérifier si LVM est configuré
if ! lvdisplay "/dev/$VG_NAME/$LV_HOME" >/dev/null 2>&1; then
    echo "ERREUR: LVM non configuré ou volume non trouvé"
    echo "Configurer d'abord LVM avec:"
    echo "  pvcreate /dev/sdX"
    echo "  vgcreate $VG_NAME /dev/sdX"
    echo "  lvcreate -L 20G -n $LV_HOME $VG_NAME"
    echo "  mkfs.ext4 /dev/$VG_NAME/$LV_HOME"
    echo "  mount /dev/$VG_NAME/$LV_HOME /home"
    exit 1
fi

SNAPSHOT_NAME="${LV_HOME}_snapshot_$(date +%Y%m%d_%H%M%S)"
SNAPSHOT_SIZE="5G"
BACKUP_ROOT="/mnt/backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Création du snapshot LVM: $SNAPSHOT_NAME"
if ! lvcreate --snapshot --name "$SNAPSHOT_NAME" --size "$SNAPSHOT_SIZE" "/dev/$VG_NAME/$LV_HOME"; then
    echo "Échec de la création du snapshot"
    exit 1
fi

# Monter le snapshot
mkdir -p /mnt/snapshot
if ! mount -o ro "/dev/$VG_NAME/$SNAPSHOT_NAME" /mnt/snapshot; then
    echo "Échec du montage du snapshot"
    lvremove -f "/dev/$VG_NAME/$SNAPSHOT_NAME"
    exit 1
fi

# Sauvegarde depuis le snapshot
BACKUP_PATH="$BACKUP_ROOT/lvm_$DATE"
mkdir -p "$BACKUP_PATH/homes"

echo "Sauvegarde depuis le snapshot..."
tar --create \
    --preserve-permissions \
    --xattrs \
    --acls \
    --selinux \
    --numeric-owner \
    --gzip \
    --file="$BACKUP_PATH/homes/homes_lvm_$DATE.tar.gz" \
    --directory=/mnt/snapshot .

# Vérification
if tar -tzf "$BACKUP_PATH/homes/homes_lvm_$DATE.tar.gz" >/dev/null 2>&1; then
    echo "✅ Sauvegarde LVM réussie: $(du -h $BACKUP_PATH/homes/homes_lvm_$DATE.tar.gz | cut -f1)"
else
    echo "❌ Échec de la sauvegarde LVM"
fi

# Nettoyage
umount /mnt/snapshot
lvremove -f "/dev/$VG_NAME/$SNAPSHOT_NAME"
rmdir /mnt/snapshot

echo "Snapshot LVM nettoyé"
EOF
    
    chmod +x /usr/local/bin/backup_lvm.sh
    
    echo ""
    echo "SCRIPT LVM CRÉÉ :"
    echo "---------------"
    echo "/usr/local/bin/backup_lvm.sh"
    echo ""
    echo "PRÉREQUIS :"
    echo "  • LVM configuré avec un volume group 'vg00'"
    echo "  • Logical volume 'lv_home' monté sur /home"
    echo "  • Espace libre dans le volume group"
    echo ""
    echo "Pour configurer LVM :"
    echo "  1. pvcreate /dev/sdb1"
    echo "  2. vgcreate vg00 /dev/sdb1"
    echo "  3. lvcreate -L 20G -n lv_home vg00"
    echo "  4. mkfs.ext4 /dev/vg00/lv_home"
    echo "  5. mount /dev/vg00/lv_home /home"
    
    success "Script LVM créé (configuration manuelle requise) !"
}

# -------------------------------------------------------------------
# MENU PRINCIPAL
# -------------------------------------------------------------------
show_menu() {
    clear
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║         TP6 - SAUVEGARDE ET RESTAURATION             ║"
    echo "║              Script d'exécution                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    echo "Logs: $LOG_FILE"
    echo ""
    echo "EXERCICES PRATIQUES :"
    echo "1.  Exercices 6.6-6.7 : Configurer le disque de backup"
    echo "2.  Exercice 6.8      : Afficher la critique de la méthode"
    echo "3.  Exercice 6.9      : Organiser les fichiers de backup"
    echo "4.  Exercice 6.17     : Configurer cron (toutes les 2 min)"
    echo "5.  Exercice 6.18     : Générer backups test (full + incr)"
    echo "6.  Exercices 6.19-20 : Configurer la restauration"
    echo "7.  Exercice 6.21     : LVM Snapshots (bonus)"
    echo ""
    echo "TESTS DES FONCTIONS :"
    echo "8.  Tester backup homes"
    echo "9.  Tester backup MySQL"
    echo "10. Tester backup LDAP"
    echo "11. Tester checksums"
    echo ""
    echo "12. TOUT exécuter (sauf tests)"
    echo "13. Vérifier l'état du système"
    echo "14. Quitter"
    echo ""
}

# -------------------------------------------------------------------
# TESTS DES FONCTIONS
# -------------------------------------------------------------------
test_backup_homes() {
    log "=== TEST BACKUP HOMES ==="
    TEST_DIR="$BACKUP_ROOT/test_$(date +%s)"
    mkdir -p "$TEST_DIR"
    backup_homes "full" "$TEST_DIR"
    echo "Test terminé dans: $TEST_DIR"
}

test_backup_mysql() {
    log "=== TEST BACKUP MYSQL ==="
    TEST_DIR="$BACKUP_ROOT/test_$(date +%s)"
    mkdir -p "$TEST_DIR/mysql"
    backup_mysql "$TEST_DIR"
    echo "Test terminé dans: $TEST_DIR"
}

test_backup_ldap() {
    log "=== TEST BACKUP LDAP ==="
    TEST_DIR="$BACKUP_ROOT/test_$(date +%s)"
    mkdir -p "$TEST_DIR/ldap"
    backup_ldap "$TEST_DIR"
    echo "Test terminé dans: $TEST_DIR"
}

test_checksums() {
    log "=== TEST CHECKSUMS ==="
    TEST_DIR="$BACKUP_ROOT/test_$(date +%s)"
    mkdir -p "$TEST_DIR"/{test,checksums}
    echo "Test file" > "$TEST_DIR/test/test.txt"
    echo "find \"$TEST_DIR\" -type f -exec sha256sum {} \\; > \"$TEST_DIR/checksums/checksums.sha256\""
    find "$TEST_DIR" -type f -exec sha256sum {} \; > "$TEST_DIR/checksums/checksums.sha256"
    echo "Checksums générés dans: $TEST_DIR/checksums/"
}

# -------------------------------------------------------------------
# TOUT EXÉCUTER
# -------------------------------------------------------------------
execute_all() {
    log "=== EXÉCUTION COMPLÈTE DU TP6 ==="
    
    exercice_6_6_7
    echo ""
    
    exercice_6_8
    read -p "Appuyez sur Entrée pour continuer..."
    
    exercice_6_9
    echo ""
    
    exercice_6_17
    echo ""
    
    exercice_6_18
    echo ""
    
    exercice_6_19_20
    echo ""
    
    exercice_6_21
    echo ""
    
    success "=== TOUTES LES ÉTAPES ONT ÉTÉ EXÉCUTÉES ==="
    echo ""
    echo "RÉSUMÉ :"
    echo "  • Disque configuré : $BACKUP_ROOT"
    echo "  • Cron configuré : /etc/cron.d/tp6-backup-test"
    echo "  • Script backup : /usr/local/bin/backup_tp6.sh"
    echo "  • Script restauration : /usr/local/bin/restore_tp6.sh"
    echo "  • Script LVM : /usr/local/bin/backup_lvm.sh"
    echo ""
    echo "Logs disponibles dans: $LOG_FILE"
}

# -------------------------------------------------------------------
# VÉRIFICATION SYSTÈME
# -------------------------------------------------------------------
check_system() {
    log "=== VÉRIFICATION SYSTÈME ==="
    
    echo "1. Vérification du disque de backup..."
    if mountpoint -q "$BACKUP_ROOT"; then
        success "$BACKUP_ROOT est monté"
        df -h "$BACKUP_ROOT"
    else
        error "$BACKUP_ROOT n'est PAS monté"
    fi
    
    echo ""
    echo "2. Vérification des scripts..."
    for script in /usr/local/bin/backup_tp6.sh /usr/local/bin/restore_tp6.sh; do
        if [ -f "$script" ]; then
            success "$script existe"
        else
            warning "$script manquant"
        fi
    done
    
    echo ""
    echo "3. Vérification de cron..."
    if [ -f "/etc/cron.d/tp6-backup-test" ]; then
        success "Configuration cron trouvée"
        echo "Contenu:"
        cat /etc/cron.d/tp6-backup-test
    else
        warning "Configuration cron manquante"
    fi
    
    echo ""
    echo "4. Backups existants..."
    backups=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*full*" -o -name "*incr*" -o -name "*test*" | head -5)
    if [ -n "$backups" ]; then
        success "Backups trouvés:"
        for backup in $backups; do
            echo "  - $(basename "$backup")"
        done
    else
        warning "Aucun backup trouvé"
    fi
    
    echo ""
    success "Vérification terminée"
}

# -------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------
main() {
    # Initialisation
    check_root
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    clear
    echo "TP6 - Script d'exécution"
    echo "========================"
    echo ""
    echo "Ce script va exécuter toutes les étapes pratiques du TP6."
    echo "Les logs seront écrits dans: $LOG_FILE"
    echo ""
    read -p "Appuyez sur Entrée pour continuer..." dummy
    
    while true; do
        show_menu
        read -p "Votre choix [1-14]: " choice
        
        case $choice in
            1) exercice_6_6_7 ;;
            2) exercice_6_8 ;;
            3) exercice_6_9 ;;
            4) exercice_6_17 ;;
            5) exercice_6_18 ;;
            6) exercice_6_19_20 ;;
            7) exercice_6_21 ;;
            8) test_backup_homes ;;
            9) test_backup_mysql ;;
            10) test_backup_ldap ;;
            11) test_checksums ;;
            12) execute_all ;;
            13) check_system ;;
            14) 
                echo ""
                echo "Au revoir !"
                echo "Logs disponibles dans: $LOG_FILE"
                exit 0
                ;;
            *) 
                echo "Choix invalide !"
                sleep 1
                ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..." dummy
    done
}

# Exécuter le script
main "$@"