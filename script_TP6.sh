#!/bin/bash
# ============================================================================
# TP6 - SAUVEGARDE ET RESTAURATION COMPLÈTE
# Système Gentoo - Serveur ISTYCORP
# ============================================================================
# Ce script implémente tous les exercices du TP6 de sauvegarde/restauration
# Inclut : Backup complet, incrémental, différentiel, LVM, restauration, monitoring
# ============================================================================

# ----------------------------------------------------------------------------
# CONFIGURATION PRINCIPALE
# ----------------------------------------------------------------------------
BACKUP_ROOT="/mnt/backup"
LOG_DIR="/var/log/backup"
CONFIG_FILE="/etc/backup_tp6.conf"
LOCK_FILE="/var/run/backup_tp6.lock"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30
SCRIPT_VERSION="TP6-v1.0"

# ----------------------------------------------------------------------------
# FONCTIONS DE BASE
# ----------------------------------------------------------------------------

# Initialisation du système
init_system() {
    echo "=== TP6 - SAUVEGARDE ET RESTAURATION ==="
    echo "Script: $SCRIPT_VERSION"
    echo "Date: $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Utilisateur: $(whoami)"
    echo "Hostname: $(hostname)"
    echo ""
    
    # Création des répertoires
    mkdir -p "$BACKUP_ROOT" "$LOG_DIR"
    
    # Vérification des droits
    if [ "$EUID" -ne 0 ]; then
        echo "ERREUR: Ce script doit être exécuté en tant que root"
        exit 1
    fi
    
    # Vérification du verrou pour éviter les exécutions multiples
    if [ -f "$LOCK_FILE" ]; then
        echo "ERREUR: Une sauvegarde est déjà en cours"
        exit 1
    fi
    echo "$$" > "$LOCK_FILE"
    
    # Chargement de la configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        create_default_config
    fi
}

# Nettoyage
cleanup() {
    rm -f "$LOCK_FILE"
    echo "Nettoyage terminé"
}

# Logging
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOG_DIR/backup_$(date +%Y%m).log"
    
    case $level in
        "INFO") echo -e "\e[32m[$timestamp] $message\e[0m" ;;
        "WARN") echo -e "\e[33m[$timestamp] $message\e[0m" ;;
        "ERROR") echo -e "\e[31m[$timestamp] $message\e[0m" ;;
        *) echo "[$timestamp] $message" ;;
    esac
    
    echo "[$timestamp] $level: $message" >> "$log_file"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.6-6.7 : CONFIGURATION DU DISQUE DE BACKUP
# ----------------------------------------------------------------------------
configure_backup_disk() {
    log "INFO" "=== EXERCICE 6.6-6.7: Configuration du disque de backup ==="
    
    echo "Disques disponibles:"
    lsblk
    
    read -p "Nom du disque à utiliser (ex: sdb): " DISK_NAME
    read -p "Taille de la partition (ex: 50G): " PART_SIZE
    
    if [ -z "$DISK_NAME" ] || [ -z "$PART_SIZE" ]; then
        log "ERROR" "Configuration annulée"
        return 1
    fi
    
    # Partitionnement
    log "INFO" "Partitionnement de /dev/$DISK_NAME..."
    fdisk "/dev/$DISK_NAME" << EOF
n
p
1

+${PART_SIZE}
w
EOF
    
    # Formatage
    log "INFO" "Formatage en ext4..."
    mkfs.ext4 "/dev/${DISK_NAME}1"
    e2label "/dev/${DISK_NAME}1" "BACKUP_TP6"
    
    # Montage
    log "INFO" "Configuration du montage..."
    echo "LABEL=BACKUP_TP6 $BACKUP_ROOT ext4 defaults,noatime 0 2" >> /etc/fstab
    mkdir -p "$BACKUP_ROOT"
    mount "$BACKUP_ROOT"
    
    log "INFO" "Disque de backup configuré avec succès"
    df -h "$BACKUP_ROOT"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.9 : ORGANISATION DES FICHIERS DE BACKUP
# ----------------------------------------------------------------------------
create_backup_structure() {
    local backup_type=$1
    local backup_path="$BACKUP_ROOT/${DATE}_${backup_type}"
    
    log "INFO" "=== EXERCICE 6.9: Organisation des fichiers de backup ==="
    log "INFO" "Création de la structure: $backup_path"
    
    # Structure recommandée du TP
    mkdir -p "$backup_path"/{homes,mysql,ldap,wordpress,logs,metadata,system}
    
    # Fichiers de métadonnées
    echo "type: $backup_type" > "$backup_path/metadata/backup_info.txt"
    echo "date: $DATE" >> "$backup_path/metadata/backup_info.txt"
    echo "hostname: $(hostname)" >> "$backup_path/metadata/backup_info.txt"
    
    # Informations système
    uname -a > "$backup_path/system/uname.txt"
    df -h > "$backup_path/system/disk_usage.txt"
    free -h > "$backup_path/system/memory.txt"
    
    echo "$backup_path"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.10 : SAUVEGARDE DES HOMES UTILISATEURS
# ----------------------------------------------------------------------------
backup_homes() {
    local backup_type=$1
    local backup_path=$2
    
    log "INFO" "=== EXERCICE 6.10: Sauvegarde des homes utilisateurs ==="
    
    local snapshot_file="$BACKUP_ROOT/homes_snapshot.sn"
    local backup_file=""
    
    case $backup_type in
        "full")
            log "INFO" "Sauvegarde complète des homes"
            backup_file="$backup_path/homes/homes_full_${DATE}.tar.gz"
            
            # Tar avec préservation complète des attributs
            tar --create \
                --preserve-permissions \
                --xattrs \
                --acls \
                --selinux \
                --numeric-owner \
                --listed-incremental="$snapshot_file" \
                --gzip \
                --file="$backup_file" \
                --directory="/home" . 2>> "$backup_path/logs/homes.log"
            
            # Marquer comme dernière sauvegarde complète
            echo "$backup_path" > "$BACKUP_ROOT/last_full_backup.txt"
            ;;
            
        "incremental")
            log "INFO" "Sauvegarde incrémentale des homes"
            
            # Vérifier l'existence d'une sauvegarde complète
            if [ ! -f "$snapshot_file" ]; then
                log "WARN" "Aucune sauvegarde complète trouvée, conversion en full"
                backup_type="full"
                backup_homes "full" "$backup_path"
                return
            fi
            
            backup_file="$backup_path/homes/homes_incr_${DATE}.tar.gz"
            
            tar --create \
                --preserve-permissions \
                --xattrs \
                --acls \
                --selinux \
                --numeric-owner \
                --listed-incremental="$snapshot_file" \
                --gzip \
                --file="$backup_file" \
                --directory="/home" . 2>> "$backup_path/logs/homes.log"
            ;;
    esac
    
    # Vérification
    if [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "INFO" "Sauvegarde homes terminée: $size"
        
        # Test d'intégrité
        if tar -tzf "$backup_file" > /dev/null 2>&1; then
            log "INFO" "Archive vérifiée avec succès"
        else
            log "ERROR" "Archive corrompue!"
            return 1
        fi
    else
        log "ERROR" "Échec de la création de l'archive"
        return 1
    fi
    
    return 0
}

# ----------------------------------------------------------------------------
# EXERCICE 6.12 : SAUVEGARDE MYSQL
# ----------------------------------------------------------------------------
backup_mysql() {
    local backup_path=$1
    
    log "INFO" "=== EXERCICE 6.12: Sauvegarde des bases MySQL ==="
    
    # Vérifier si MySQL est en cours d'exécution
    if ! systemctl is-active --quiet mysql 2>/dev/null && ! systemctl is-active --quiet mariadb 2>/dev/null; then
        log "WARN" "MySQL/MariaDB n'est pas en cours d'exécution"
        return 1
    fi
    
    # Obtenir la liste des bases de données
    local databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
    
    if [ -z "$databases" ]; then
        log "ERROR" "Impossible de récupérer la liste des bases de données"
        return 1
    fi
    
    local total_size=0
    local db_count=0
    
    # Sauvegarde de chaque base
    for db in $databases; do
        log "INFO" "Sauvegarde de la base: $db"
        
        local db_file="$backup_path/mysql/${db}_${DATE}.sql.gz"
        
        # Utilisation de --single-transaction pour la cohérence (Exercice 6.13)
        mysqldump --single-transaction \
                  --routines \
                  --triggers \
                  --events \
                  --add-drop-database \
                  --databases "$db" | gzip > "$db_file"
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            local size=$(du -h "$db_file" | cut -f1)
            log "INFO" "  ✓ $db : $size"
            total_size=$((total_size + $(du -k "$db_file" | cut -f1)))
            ((db_count++))
        else
            log "ERROR" "  ✗ Échec de la sauvegarde de $db"
        fi
    done
    
    # Sauvegarde complète de toutes les bases
    log "INFO" "Sauvegarde complète de toutes les bases"
    mysqldump --single-transaction \
              --routines \
              --triggers \
              --events \
              --all-databases | gzip > "$backup_path/mysql/all_databases_${DATE}.sql.gz"
    
    log "INFO" "Sauvegarde MySQL terminée: $db_count bases, $(echo "scale=1; $total_size/1024" | bc)MB total"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.15 : SAUVEGARDE LDAP
# ----------------------------------------------------------------------------
backup_ldap() {
    local backup_path=$1
    
    log "INFO" "=== EXERCICE 6.15: Sauvegarde de la base LDAP ==="
    
    # Vérifier si slapd est en cours d'exécution
    if ! systemctl is-active --quiet slapd 2>/dev/null; then
        log "WARN" "LDAP n'est pas en cours d'exécution"
        return 1
    fi
    
    # Méthode 1: slapcat (recommandée)
    local ldif_file="$backup_path/ldap/ldap_${DATE}.ldif"
    
    if command -v slapcat > /dev/null 2>&1; then
        log "INFO" "Utilisation de slapcat pour l'export LDAP"
        slapcat -v -l "$ldif_file" 2>> "$backup_path/logs/ldap.log"
        
        if [ $? -eq 0 ]; then
            # Compression
            gzip "$ldif_file"
            local size=$(du -h "${ldif_file}.gz" | cut -f1)
            log "INFO" "Export LDAP réussi: $size"
        else
            log "ERROR" "Échec de slapcat"
            return 1
        fi
    else
        # Méthode 2: ldapsearch
        log "INFO" "Utilisation de ldapsearch pour l'export LDAP"
        ldapsearch -x -H ldap://localhost -b "dc=isty,dc=com" > "$ldif_file"
        gzip "$ldif_file"
    fi
    
    # Sauvegarde de la configuration
    if [ -d "/etc/openldap" ]; then
        tar -czf "$backup_path/ldap/ldap_config_${DATE}.tar.gz" -C /etc openldap
        log "INFO" "Configuration LDAP sauvegardée"
    fi
    
    return 0
}

# ----------------------------------------------------------------------------
# EXERCICE 6.16 : GENERATION DE CHECKSUMS
# ----------------------------------------------------------------------------
generate_checksums() {
    local backup_path=$1
    
    log "INFO" "=== EXERCICE 6.16: Génération de checksums ==="
    
    # SHA256 pour tous les fichiers de sauvegarde
    find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
        -exec sha256sum {} \; > "$backup_path/checksums_${DATE}.sha256"
    
    # Vérification
    if cd "$backup_path" && sha256sum -c "checksums_${DATE}.sha256" > /dev/null 2>&1; then
        log "INFO" "Checksums vérifiés avec succès"
        
        # MD5 additionnel
        find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
            -exec md5sum {} \; > "$backup_path/checksums_${DATE}.md5"
            
        return 0
    else
        log "ERROR" "Erreur de vérification des checksums"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.21 BONUS : LVM SNAPSHOTS
# ----------------------------------------------------------------------------
create_lvm_snapshot() {
    log "INFO" "=== EXERCICE 6.21 BONUS: Création de snapshot LVM ==="
    
    # Vérifier si LVM est disponible
    if ! command -v lvcreate > /dev/null 2>&1; then
        log "WARN" "LVM n'est pas installé"
        return 1
    fi
    
    # Chercher un volume logique contenant /home
    local home_lv=$(df /home | awk 'NR==2 {print $1}')
    
    if [[ $home_lv =~ /dev/mapper/ ]]; then
        local vg_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f1)
        local lv_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f2)
        
        log "INFO" "Détection LVM: VG=$vg_name, LV=$lv_name"
        
        # Créer le snapshot
        local snapshot_name="${lv_name}_snapshot_${DATE}"
        
        if lvcreate --snapshot --name "$snapshot_name" --size 5G "/dev/$vg_name/$lv_name" > /dev/null 2>&1; then
            log "INFO" "Snapshot LVM créé: $snapshot_name"
            echo "/dev/$vg_name/$snapshot_name"
            return 0
        else
            log "ERROR" "Échec de la création du snapshot"
            return 1
        fi
    else
        log "INFO" "/home n'est pas sur un volume LVM"
        return 1
    fi
}

remove_lvm_snapshot() {
    local snapshot_path=$1
    
    if [ -n "$snapshot_path" ]; then
        log "INFO" "Suppression du snapshot LVM"
        lvremove -f "$snapshot_path" > /dev/null 2>&1
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.18 : GENERATION DE BACKUP
# ----------------------------------------------------------------------------
perform_backup() {
    local backup_type=$1
    
    log "INFO" "=== EXERCICE 6.18: Génération de backup ($backup_type) ==="
    
    # Créer la structure
    local backup_path=$(create_backup_structure "$backup_type")
    
    # Sauvegarde LVM snapshot si disponible
    local snapshot_path=""
    if [ "$backup_type" = "full" ]; then
        snapshot_path=$(create_lvm_snapshot)
    fi
    
    # Exécuter les sauvegardes
    local errors=0
    
    log "INFO" "1. Sauvegarde des homes utilisateurs"
    if ! backup_homes "$backup_type" "$backup_path"; then
        ((errors++))
    fi
    
    log "INFO" "2. Sauvegarde MySQL"
    if ! backup_mysql "$backup_path"; then
        ((errors++))
    fi
    
    log "INFO" "3. Sauvegarde LDAP"
    if ! backup_ldap "$backup_path"; then
        ((errors++))
    fi
    
    log "INFO" "4. Sauvegarde WordPress (simulée)"
    # Simulation - à adapter avec vos chemins
    if [ -d "/var/www/wordpress" ]; then
        tar -czf "$backup_path/wordpress/wp_files_${DATE}.tar.gz" -C /var/www wordpress
    fi
    
    log "INFO" "5. Génération des checksums"
    if ! generate_checksums "$backup_path"; then
        ((errors++))
    fi
    
    # Nettoyer le snapshot LVM
    remove_lvm_snapshot "$snapshot_path"
    
    # Rapport final
    local total_size=$(du -sh "$backup_path" | cut -f1)
    
    log "INFO" "=== BACKUP $backup_type TERMINÉ ==="
    log "INFO" "Emplacement: $backup_path"
    log "INFO" "Taille totale: $total_size"
    log "INFO" "Erreurs: $errors"
    
    # Sauvegarder le rapport
    {
        echo "RAPPORT DE SAUVEGARDE"
        echo "====================="
        echo "Type: $backup_type"
        echo "Date: $DATE"
        echo "Chemin: $backup_path"
        echo "Taille: $total_size"
        echo "Erreurs: $errors"
        echo ""
        echo "CONTENU:"
        find "$backup_path" -type f -name "*.gz" -o -name "*.tar" | while read f; do
            echo "  $(basename "$f") - $(du -h "$f" | cut -f1)"
        done
    } > "$backup_path/backup_report.txt"
    
    return $errors
}

# ----------------------------------------------------------------------------
# EXERCICE 6.20 : RESTAURATION UTILISATEUR SPECIFIQUE
# ----------------------------------------------------------------------------
restore_user_files() {
    local user=$1
    local backup_date=$2
    
    log "INFO" "=== EXERCICE 6.20: Restauration de l'utilisateur '$user' ==="
    
    if [ -z "$user" ]; then
        log "ERROR" "Nom d'utilisateur non spécifié"
        return 1
    fi
    
    # Chercher le dernier backup complet
    local last_full=$(cat "$BACKUP_ROOT/last_full_backup.txt" 2>/dev/null)
    
    if [ -z "$last_full" ]; then
        last_full=$(find "$BACKUP_ROOT" -type d -name "*_full" | sort -r | head -1)
    fi
    
    if [ -z "$last_full" ] || [ ! -d "$last_full" ]; then
        log "ERROR" "Aucune sauvegarde complète trouvée"
        return 1
    fi
    
    # Chercher le home de l'utilisateur dans la sauvegarde complète
    local user_backup=$(find "$last_full/homes" -name "homes_full_*.tar.gz" | head -1)
    
    if [ ! -f "$user_backup" ]; then
        log "ERROR" "Aucune sauvegarde de homes trouvée"
        return 1
    fi
    
    log "INFO" "Restauration depuis: $(basename "$user_backup")"
    
    # Sauvegarder les fichiers actuels
    if [ -d "/home/$user" ]; then
        local backup_dir="/home/${user}_backup_$(date +%Y%m%d_%H%M%S)"
        log "INFO" "Sauvegarde des fichiers actuels vers: $backup_dir"
        cp -r "/home/$user" "$backup_dir"
    fi
    
    # Extraire seulement le répertoire de l'utilisateur
    if tar -tzf "$user_backup" | grep -q "^home/$user/"; then
        log "INFO" "Extraction des fichiers de $user..."
        
        # Créer le répertoire s'il n'existe pas
        mkdir -p "/home/$user"
        
        # Extraire avec préservation des attributs
        tar -xzf "$user_backup" \
            --directory="/" \
            --preserve-permissions \
            --xattrs \
            --acls \
            --selinux \
            "home/$user"
        
        # Restaurer les permissions
        chown -R "$user:$user" "/home/$user"
        
        log "INFO" "Restauration terminée pour l'utilisateur $user"
        echo "=== RÉSUMÉ DE LA RESTAURATION ==="
        echo "Utilisateur: $user"
        echo "Source: $(basename "$user_backup")"
        echo "Destination: /home/$user"
        echo "Taille restaurée: $(du -sh "/home/$user" | cut -f1)"
        if [ -n "$backup_dir" ]; then
            echo "Anciens fichiers sauvegardés dans: $backup_dir"
        fi
        
        return 0
    else
        log "ERROR" "L'utilisateur $user n'a pas été trouvé dans la sauvegarde"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.19 : RESTAURATION COMPLÈTE
# ----------------------------------------------------------------------------
restore_full_backup() {
    local backup_date=$1
    
    log "INFO" "=== EXERCICE 6.19: Restauration complète ==="
    
    # Chercher le backup correspondant
    local backup_path=$(find "$BACKUP_ROOT" -type d -name "*${backup_date}*" | head -1)
    
    if [ -z "$backup_path" ] || [ ! -d "$backup_path" ]; then
        log "ERROR" "Backup non trouvé pour la date: $backup_date"
        return 1
    fi
    
    log "INFO" "Restauration depuis: $backup_path"
    
    # Vérifier les checksums
    local checksum_file=$(find "$backup_path" -name "checksums_*.sha256" | head -1)
    if [ -f "$checksum_file" ]; then
        log "INFO" "Vérification de l'intégrité..."
        if ! sha256sum -c "$checksum_file" > /dev/null 2>&1; then
            log "ERROR" "Échec de la vérification d'intégrité"
            return 1
        fi
    fi
    
    # Menu de restauration
    echo "=== MENU DE RESTAURATION ==="
    echo "1. Restaurer uniquement les homes"
    echo "2. Restaurer uniquement MySQL"
    echo "3. Restaurer uniquement LDAP"
    echo "4. Restaurer tout"
    echo "5. Annuler"
    echo ""
    read -p "Choix [1-5]: " choice
    
    case $choice in
        1)
            log "INFO" "Restauration des homes..."
            local home_backup=$(find "$backup_path/homes" -name "*.tar.gz" | head -1)
            if [ -f "$home_backup" ]; then
                tar -xzf "$home_backup" -C /
            fi
            ;;
        2)
            log "INFO" "Restauration MySQL..."
            # À implémenter selon votre configuration
            ;;
        3)
            log "INFO" "Restauration LDAP..."
            # À implémenter selon votre configuration
            ;;
        4)
            log "INFO" "Restauration complète..."
            # Restaurer les homes
            local home_backup=$(find "$backup_path/homes" -name "*.tar.gz" | head -1)
            if [ -f "$home_backup" ]; then
                tar -xzf "$home_backup" -C /
            fi
            # Autres restaurations...
            ;;
        5)
            log "INFO" "Restauration annulée"
            return 0
            ;;
        *)
            log "ERROR" "Choix invalide"
            return 1
            ;;
    esac
    
    log "INFO" "Restauration terminée"
    return 0
}

# ----------------------------------------------------------------------------
# EXERCICE 6.17 : CONFIGURATION CRON
# ----------------------------------------------------------------------------
setup_cron() {
    log "INFO" "=== EXERCICE 6.17: Configuration de cron ==="
    
    local cron_file="/etc/cron.d/tp6-backup"
    
    cat > "$cron_file" << EOF
# TP6 - Planning de sauvegarde automatisé
# Format: minute heure jour_mois mois jour_semaine utilisateur commande

# Sauvegarde complète: Dimanche à 2h00
0 2 * * 0 root /usr/local/bin/tp6-backup.sh full

# Sauvegarde incrémentale: Lundi-Samedi à 2h00
0 2 * * 1-6 root /usr/local/bin/tp6-backup.sh incremental

# Nettoyage des anciennes sauvegardes: 1er du mois à 3h00
0 3 1 * * root /usr/local/bin/tp6-backup.sh cleanup

# Vérification des sauvegardes: Vendredi à 5h00
0 5 * * 5 root /usr/local/bin/tp6-backup.sh verify

# Test de restauration: 1er Samedi du mois à 6h00
0 6 * * 6 root /usr/local/bin/tp6-backup.sh test-restore
EOF
    
    log "INFO" "Configuration cron créée: $cron_file"
    echo "Contenu du fichier cron:"
    cat "$cron_file"
    echo ""
    echo "Pour appliquer: systemctl restart cron"
}

# ----------------------------------------------------------------------------
# FONCTIONS UTILITAIRES
# ----------------------------------------------------------------------------
show_help() {
    cat << EOF
TP6 - Système de Sauvegarde et Restauration
Usage: $0 [COMMANDE] [OPTIONS]

Commandes:
  init              Initialiser le système de backup
  full              Sauvegarde complète (Exercice 6.18)
  incremental       Sauvegarde incrémentale
  configure-disk    Configurer le disque de backup (Exercices 6.6-6.7)
  setup-cron        Configurer les tâches cron (Exercice 6.17)
  
  restore-user USER [DATE] Restaurer un utilisateur (Exercice 6.20)
  restore-full DATE        Restauration complète (Exercice 6.19)
  
  list              Lister les sauvegardes disponibles
  verify            Vérifier l'intégrité des sauvegardes
  cleanup           Nettoyer les anciennes sauvegardes
  status            Statut du système de backup
  help              Afficher cette aide

Exemples:
  $0 configure-disk        # Configurer le disque de backup
  $0 full                  # Sauvegarde complète
  $0 incremental           # Sauvegarde incrémentale
  $0 restore-user raj      # Restaurer l'utilisateur 'raj'
  $0 list                  # Lister les sauvegardes

Planification recommandée:
  - Dimanche 2h: Backup complet
  - Lundi-Samedi 2h: Backup incrémental
  - 1er du mois: Nettoyage

EOF
}

list_backups() {
    log "INFO" "=== LISTE DES SAUVEGARDES DISPONIBLES ==="
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        log "ERROR" "Répertoire de backup non trouvé"
        return 1
    fi
    
    echo "Type    Date                Taille    Chemin"
    echo "------  ------------------  --------  --------------------"
    
    find "$BACKUP_ROOT" -type d -name "*_full" -o -name "*_incr" | sort | while read dir; do
        if [ -d "$dir" ]; then
            local type=$(basename "$dir" | cut -d_ -f2)
            local date=$(basename "$dir" | cut -d_ -f1)
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            printf "%-8s %-18s %-9s %s\n" "$type" "$date" "$size" "$dir"
        fi
    done
    
    echo ""
    echo "Dernière sauvegarde complète: $(cat $BACKUP_ROOT/last_full_backup.txt 2>/dev/null || echo "Non trouvée")"
}

cleanup_old_backups() {
    log "INFO" "Nettoyage des sauvegardes de plus de $RETENTION_DAYS jours..."
    
    find "$BACKUP_ROOT" -type d -name "*_full" -o -name "*_incr" | while read dir; do
        if [ -d "$dir" ]; then
            local dir_name=$(basename "$dir")
            local dir_date=$(echo "$dir_name" | grep -oE '^[0-9]{8}')
            
            if [ -n "$dir_date" ]; then
                local dir_epoch=$(date -d "${dir_date:0:4}-${dir_date:4:2}-${dir_date:6:2}" +%s 2>/dev/null)
                local current_epoch=$(date +%s)
                local age_days=$(( (current_epoch - dir_epoch) / 86400 ))
                
                if [ $age_days -gt $RETENTION_DAYS ]; then
                    log "INFO" "Suppression: $dir (âge: $age_days jours)"
                    rm -rf "$dir"
                fi
            fi
        fi
    done
    
    log "INFO" "Nettoyage terminé"
}

verify_backups() {
    log "INFO" "=== VÉRIFICATION DES SAUVEGARDES ==="
    
    local errors=0
    
    # Vérifier la dernière sauvegarde complète
    local last_full=$(cat "$BACKUP_ROOT/last_full_backup.txt" 2>/dev/null)
    if [ -n "$last_full" ] && [ -d "$last_full" ]; then
        log "INFO" "Vérification de la dernière sauvegarde complète: $last_full"
        
        local checksum_file=$(find "$last_full" -name "checksums_*.sha256" | head -1)
        if [ -f "$checksum_file" ]; then
            if sha256sum -c "$checksum_file" > /dev/null 2>&1; then
                log "INFO" "✓ Intégrité vérifiée"
            else
                log "ERROR" "✗ Problème d'intégrité détecté"
                ((errors++))
            fi
        fi
    else
        log "WARN" "Aucune sauvegarde complète trouvée"
    fi
    
    # Vérifier l'espace disque
    local disk_usage=$(df "$BACKUP_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log "ERROR" "✗ Espace disque critique: ${disk_usage}% utilisé"
        ((errors++))
    elif [ "$disk_usage" -gt 80 ]; then
        log "WARN" "⚠ Espace disque élevé: ${disk_usage}% utilisé"
    else
        log "INFO" "✓ Espace disque OK: ${disk_usage}% utilisé"
    fi
    
    # Vérifier les permissions
    if [ -d "$BACKUP_ROOT" ]; then
        local perms=$(stat -c "%a" "$BACKUP_ROOT")
        if [ "$perms" = "700" ] || [ "$perms" = "750" ]; then
            log "INFO" "✓ Permissions OK: $perms"
        else
            log "WARN" "⚠ Permissions non sécurisées: $perms"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log "INFO" "=== VÉRIFICATION TERMINÉE - TOUT EST OK ==="
        return 0
    else
        log "ERROR" "=== VÉRIFICATION TERMINÉE - $errors ERREUR(S) ==="
        return 1
    fi
}

system_status() {
    log "INFO" "=== STATUT DU SYSTÈME DE BACKUP ==="
    
    echo "1. Informations système:"
    echo "   Date: $(date)"
    echo "   Hostname: $(hostname)"
    echo "   Utilisateur: $(whoami)"
    echo ""
    
    echo "2. Répertoire de backup:"
    if [ -d "$BACKUP_ROOT" ]; then
        echo "   ✓ $BACKUP_ROOT"
        echo "   Utilisation: $(df -h "$BACKUP_ROOT" | awk 'NR==2 {print $5}')"
        echo "   Permissions: $(stat -c "%a %U:%G" "$BACKUP_ROOT")"
    else
        echo "   ✗ NON CONFIGURÉ"
    fi
    echo ""
    
    echo "3. Services requis:"
    local services=("mysql" "mariadb" "slapd" "cron")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null || systemctl is-active --quiet "${service}.service" 2>/dev/null; then
            echo "   ✓ $service: ACTIF"
        else
            echo "   ✗ $service: INACTIF"
        fi
    done
    echo ""
    
    echo "4. Dernières sauvegardes:"
    list_backups | tail -10
    echo ""
    
    echo "5. Statistiques:"
    local total_backups=$(find "$BACKUP_ROOT" -type d -name "*_full" -o -name "*_incr" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)
    echo "   Nombre de sauvegardes: $total_backups"
    echo "   Taille totale: ${total_size:-0}"
    echo "   Rétention: $RETENTION_DAYS jours"
}

create_default_config() {
    log "INFO" "Création de la configuration par défaut..."
    
    cat > "$CONFIG_FILE" << EOF
# TP6 - Configuration du système de sauvegarde
# ============================================

# Chemins
BACKUP_ROOT="/mnt/backup"
LOG_DIR="/var/log/backup"

# Rétention
RETENTION_DAYS=30

# MySQL
MYSQL_USER="backup"
MYSQL_PASS=""
MYSQL_HOST="localhost"

# LDAP
LDAP_BASE="dc=isty,dc=com"
LDAP_ADMIN="cn=admin,dc=isty,dc=com"
LDAP_PASS=""

# WordPress
WORDPRESS_DIR="/var/www/wordpress"

# Notifications
NOTIFY_EMAIL="admin@istycorp.com"

# Compression
COMPRESSION_LEVEL=6

# Exclusions
EXCLUDE_PATTERNS="*.tmp *.log /tmp/* /proc/* /sys/*"

# LVM (Bonus)
USE_LVM_SNAPSHOTS="yes"
LVM_SNAPSHOT_SIZE="5G"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log "INFO" "Configuration créée: $CONFIG_FILE"
    log "INFO" "ATTENTION: Modifiez les mots de passe dans le fichier de configuration!"
}

# ----------------------------------------------------------------------------
# FONCTION PRINCIPALE
# ----------------------------------------------------------------------------
main() {
    trap cleanup EXIT INT TERM
    
    # Initialisation
    init_system
    
    # Gestion des commandes
    case "$1" in
        # Configuration
        "init")
            create_default_config
            ;;
        "configure-disk")
            configure_backup_disk
            ;;
        "setup-cron")
            setup_cron
            ;;
            
        # Sauvegardes
        "full")
            perform_backup "full"
            ;;
        "incremental")
            perform_backup "incremental"
            ;;
            
        # Restaurations
        "restore-user")
            restore_user_files "$2" "$3"
            ;;
        "restore-full")
            restore_full_backup "$2"
            ;;
            
        # Utilitaires
        "list")
            list_backups
            ;;
        "verify")
            verify_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "status")
            system_status
            ;;
        "test")
            # Mode test - Exercice 6.18
            log "INFO" "=== MODE TEST - EXERCICE 6.18 ==="
            echo "1. Génération d'un backup complet..."
            perform_backup "full"
            echo ""
            echo "2. Génération d'un backup incrémental..."
            # Créer un fichier de test
            echo "Test" > /home/test_file_$DATE.txt
            perform_backup "incremental"
            echo ""
            echo "3. Liste des sauvegardes..."
            list_backups
            ;;
            
        # Aide
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log "ERROR" "Commande inconnue: $1"
            show_help
            exit 1
            ;;
    esac
    
    # Fin
    echo ""
    log "INFO" "TP6 - Opération terminée avec succès"
    echo "Logs disponibles dans: $LOG_DIR"
}

# ----------------------------------------------------------------------------
# EXÉCUTION
# ----------------------------------------------------------------------------
if [ $# -eq 0 ]; then
    echo "TP6 - Système de Sauvegarde/Restauration"
    echo "========================================"
    echo "Pour l'aide: $0 help"
    echo ""
    echo "Commandes disponibles:"
    echo "  init          - Initialiser le système"
    echo "  full          - Backup complet"
    echo "  incremental   - Backup incrémental"
    echo "  restore-user  - Restaurer un utilisateur"
    echo "  list          - Lister les sauvegardes"
    echo "  status        - Statut du système"
    echo ""
    read -p "Voulez-vous continuer? (o/N): " choice
    case $choice in
        o|O|oui|Oui)
            show_help
            ;;
        *)
            exit 0
            ;;
    esac
else
    main "$@"
fi

# ----------------------------------------------------------------------------
# RÉPONSES AUX EXERCICES THÉORIQUES (Commentaires)
# ----------------------------------------------------------------------------

# Exercice 6.1: Sauvegarde incrémentale
# =====================================
# Une sauvegarde incrémentale ne sauvegarde que les données modifiées depuis
# la dernière sauvegarde (complète ou incrémentale). Elle utilise un fichier
# d'index pour suivre les modifications.
# Avantages: Rapide, peu d'espace utilisé
# Inconvénients: Restauration complexe (nécessite chaîne complète)

# Exercice 6.2: Planning de sauvegarde
# ====================================
# - Dimanche 2h00: Backup complet (période de faible activité)
# - Lundi-Samedi 2h00: Backup incrémentale (maintenance quotidienne)
# - 1er du mois: Backup différentielle (point de restauration mensuel)

# Exercice 6.3: Contenus et volumes
# =================================
# 1. Homes utilisateurs: /home/* - 10-50GB - tar avec attributs
# 2. MySQL: Toutes les bases - 5-20GB - mysqldump --single-transaction
# 3. LDAP: Base complète - 1-5GB - slapcat ou ldapsearch
# 4. WordPress: Fichiers + DB - 2-10GB - tar + mysqldump

# Exercice 6.4: Supports de sauvegarde
# ====================================
# - Disque dur: Rapide, capacité, réinscriptible / Mécanique, sensible
# - SSD: Très rapide, pas de pièces mobiles / Coût, durée de vie limitée
# - Bande: Faible coût/Go, durable / Lent, accès séquentiel
# - Cloud: Accès distant, redondance / Dépendance réseau, coût récurrent

# Exercice 6.5: Stockage des supports
# ===================================
# 1. Localisation physique: Hors site (protection incendie/vol)
# 2. Contrôle d'accès: Restriction physique et logique
# 3. Conditions environnementales: Température/humidité contrôlées
# 4. Rotation: Remplacer périodiquement les supports
# 5. Test de restauration: Vérifier régulièrement l'intégrité

# Exercice 6.8: Critique du stockage sur disque
# =============================================
# Avantages: Installation simple, performances, coût modéré
# Inconvénients: Pas de protection contre sinistres locaux,
#                Vulnérable aux pannes matérielles
# Amélioration: Ajouter réplication sur bande ou cloud

# Exercice 6.11: Backup sur CD/DVD
# =================================
# Précautions: Vérifier compatibilité, utiliser médias qualité archive,
#               Tester après gravure, stocker conditions appropriées,
#               Prévoir rotation (durée de vie limitée)

# Exercice 6.13: Cohérence des bases MySQL
# ========================================
# Problème: Base modifiée pendant le dump → incohérence
# Solutions: --single-transaction (InnoDB), verrouillage global,
#            Réplication avec esclave dédié, snapshots LVM,
#            Outils enterprise (Percona XtraBackup)

# Exercice 6.14: Grandes bases MySQL (>Go)
# ========================================
# Problèmes: Temps long, consommation mémoire, blocage prolongé
# Solutions: mydumper (dump parallèle), sauvegarde physique,
#            Réplication + backup esclave, partitionnement,
#            Backup incrémental binaire

# Exercice 6.20: Restauration utilisateur "raj"
# =============================================
# Commande: $0 restore-user raj
# Procédure: Identifier dernière sauvegarde contenant /home/raj,
#            Extraire seulement ce répertoire,
#            Préserver fichiers existants (backup),
#            Vérifier permissions et attributs

# Exercice 6.21: LVM Snapshots (Bonus)
# =====================================
# Implémentation: Création automatique de snapshot avant backup,
#                 Backup depuis le snapshot monté en read-only,
#                 Suppression après backup
# Avantages: Cohérence des données, pas de verrouillage fichiers,
#            Performance améliorée, restauration rapide possible