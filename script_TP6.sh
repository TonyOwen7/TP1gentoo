#!/bin/bash
# ============================================================================
# TP6 COMPLET - SAUVEGARDE ET RESTAURATION
# Script unique avec toutes les fonctionnalités du TP
# ============================================================================

set -e  # Arrêter en cas d'erreur

# ----------------------------------------------------------------------------
# CONFIGURATION GLOBALE
# ----------------------------------------------------------------------------
readonly VERSION="TP6-Complete-v2.0"
readonly CONFIG_FILE="/etc/tp6_backup.conf"
readonly BACKUP_ROOT="/mnt/backup_tp6"
readonly LOG_DIR="/var/log/tp6"
readonly LOCK_FILE="/var/run/tp6.lock"
readonly RETENTION_DAYS=30
readonly DATE=$(date +%Y%m%d_%H%M%S)

# Variables modifiables via configuration
MYSQL_USER="backup_user"
MYSQL_PASS=""
LDAP_ADMIN="cn=admin,dc=isty,dc=com"
LDAP_PASS=""
WORDPRESS_DIR="/var/www/wordpress"

# ----------------------------------------------------------------------------
# FONCTIONS D'AFFICHAGE ET LOGGING
# ----------------------------------------------------------------------------
print_header() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 TP6 - SAUVEGARDE ET RESTAURATION             ║"
    echo "║                   Script Complet - Gentoo                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

print_menu() {
    echo "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
    echo "MENU PRINCIPAL:"
    echo "──────────────────────────────────────────────────────────────────"
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOG_DIR/tp6_$(date +%Y%m).log"
    
    # Créer le répertoire de logs si nécessaire
    mkdir -p "$LOG_DIR"
    
    # Couleurs pour la console
    case $level in
        "SUCCESS") echo -e "\e[32m[$timestamp] ✓ $message\e[0m" ;;
        "INFO") echo -e "\e[34m[$timestamp] ℹ $message\e[0m" ;;
        "WARNING") echo -e "\e[33m[$timestamp] ⚠ $message\e[0m" ;;
        "ERROR") echo -e "\e[31m[$timestamp] ✗ $message\e[0m" ;;
        "DEBUG") echo -e "\e[90m[$timestamp] 🔍 $message\e[0m" ;;
        *) echo "[$timestamp] $message" ;;
    esac
    
    # Écrire dans le fichier log
    echo "[$timestamp] $level: $message" >> "$log_file"
}

# ----------------------------------------------------------------------------
# FONCTIONS D'INITIALISATION
# ----------------------------------------------------------------------------
init_system() {
    print_header
    echo "INITIALISATION DU SYSTÈME TP6"
    echo ""
    
    # Vérifier les privilèges root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "Ce script doit être exécuté en tant que root."
        echo "Utilisez: sudo $0"
        exit 1
    fi
    
    # Créer les répertoires nécessaires
    mkdir -p "$BACKUP_ROOT" "$LOG_DIR"
    chmod 750 "$BACKUP_ROOT"
    
    # Vérifier si le système est Gentoo
    if [ ! -f "/etc/gentoo-release" ]; then
        log "WARNING" "Ce script est optimisé pour Gentoo, mais le système détecté est:"
        cat /etc/os-release 2>/dev/null || echo "Système non identifié"
        read -p "Continuer malgré tout? (o/N): " choice
        [[ "$choice" != "o" && "$choice" != "O" ]] && exit 1
    fi
    
    # Charger ou créer la configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log "SUCCESS" "Configuration chargée: $CONFIG_FILE"
    else
        create_config
    fi
    
    # Vérifier les dépendances
    check_dependencies
    
    log "SUCCESS" "Système TP6 initialisé avec succès"
    sleep 2
}

create_config() {
    cat > "$CONFIG_FILE" << EOF
# Configuration TP6 - Sauvegarde et Restauration
# Généré le $(date)

# Chemins
BACKUP_ROOT="$BACKUP_ROOT"
LOG_DIR="$LOG_DIR"

# Paramètres de sauvegarde
RETENTION_DAYS=$RETENTION_DAYS
COMPRESSION_LEVEL=6

# MySQL
MYSQL_USER="$MYSQL_USER"
MYSQL_PASS="VOTRE_MOT_DE_PASSE_MYSQL_ICI"
MYSQL_HOST="localhost"

# LDAP
LDAP_ADMIN="$LDAP_ADMIN"
LDAP_PASS="VOTRE_MOT_DE_PASSE_LDAP_ICI"
LDAP_BASE="dc=isty,dc=com"

# WordPress
WORDPRESS_DIR="$WORDPRESS_DIR"

# Notifications
NOTIFY_EMAIL="admin@istycorp.com"

# LVM (Optionnel)
USE_LVM="no"
LVM_VG="vg00"
LVM_LV="lv_home"
LVM_SNAPSHOT_SIZE="5G"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log "INFO" "Fichier de configuration créé: $CONFIG_FILE"
    log "WARNING" "Modifiez les mots de passe dans: $CONFIG_FILE"
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

check_dependencies() {
    log "INFO" "Vérification des dépendances..."
    
    local missing=()
    
    # Liste des commandes requises
    local commands=(
        "tar" "gzip" "bzip2"
        "mysql" "mysqldump"
        "ldapsearch" "slapcat"
        "sha256sum" "md5sum"
        "crontab" "df" "du"
        "mount" "umount"
        "lvcreate" "lvremove"
    )
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log "WARNING" "Commandes manquantes: ${missing[*]}"
        read -p "Installer les paquets nécessaires? (O/n): " choice
        
        if [[ "$choice" != "n" && "$choice" != "N" ]]; then
            install_dependencies "${missing[@]}"
        fi
    else
        log "SUCCESS" "Toutes les dépendances sont satisfaites"
    fi
}

install_dependencies() {
    log "INFO" "Installation des dépendances sur Gentoo..."
    
    # Mettre à jour le système
    emerge --sync
    
    # Installer les paquets
    emerge -av \
        app-arch/tar \
        app-arch/gzip \
        app-arch/bzip2 \
        app-arch/pigz \
        dev-db/mysql \
        dev-db/mariadb \
        net-nds/openldap \
        app-crypt/gnupg \
        sys-process/cronie \
        sys-fs/lvm2 \
        net-misc/rsync
    
    log "SUCCESS" "Installation des dépendances terminée"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.6-6.7 : AJOUT ET CONFIGURATION DU DISQUE
# ----------------------------------------------------------------------------
exercice_6_6_7() {
    print_header
    echo "EXERCICE 6.6-6.7: AJOUT ET CONFIGURATION DU DISQUE DE BACKUP"
    echo "─────────────────────────────────────────────────────────────"
    
    echo "Étapes:"
    echo "1. Ajouter un disque dur dans VirtualBox/VMware"
    echo "2. Démarrer la VM et détecter le nouveau disque"
    echo "3. Partitionner, formater et monter le disque"
    echo ""
    
    # Afficher les disques disponibles
    echo "Disques actuellement détectés:"
    echo "──────────────────────────────"
    lsblk
    
    echo ""
    echo "Configuration automatique du disque supplémentaire:"
    echo "───────────────────────────────────────────────────"
    
    # Chercher un disque non partitionné
    local new_disk=""
    for disk in /dev/sd[b-z]; do
        if [ -b "$disk" ] && ! lsblk "$disk" | grep -q "part"; then
            new_disk="$disk"
            break
        fi
    done
    
    if [ -z "$new_disk" ]; then
        log "ERROR" "Aucun disque supplémentaire non partitionné trouvé"
        echo "Veuillez ajouter un disque dans l'interface de virtualisation"
        read -p "Appuyez sur Entrée pour retourner au menu..." dummy
        return
    fi
    
    echo "Disque détecté: $new_disk"
    read -p "Configurer ce disque pour les sauvegardes? (O/n): " choice
    
    if [[ "$choice" == "n" || "$choice" == "N" ]]; then
        return
    fi
    
    # Partitionnement
    log "INFO" "Création d'une partition unique sur $new_disk"
    parted -s "$new_disk" mklabel gpt
    parted -s "$new_disk" mkpart primary ext4 0% 100%
    
    local partition="${new_disk}1"
    sleep 2  # Attendre que la partition soit créée
    
    # Formatage
    log "INFO" "Formatage de $partition en ext4"
    mkfs.ext4 -L "BACKUP_TP6" "$partition"
    
    # Configuration du montage
    log "INFO" "Configuration du montage automatique"
    
    # Ajouter à fstab
    if ! grep -q "BACKUP_TP6" /etc/fstab; then
        echo "LABEL=BACKUP_TP6 $BACKUP_ROOT ext4 defaults,noatime 0 2" >> /etc/fstab
    fi
    
    # Monter le disque
    mkdir -p "$BACKUP_ROOT"
    mount "$BACKUP_ROOT"
    
    # Vérification
    if mountpoint -q "$BACKUP_ROOT"; then
        log "SUCCESS" "Disque configuré et monté avec succès"
        echo ""
        echo "Résumé:"
        echo "  • Disque: $new_disk"
        echo "  • Partition: $partition"
        echo "  • Point de montage: $BACKUP_ROOT"
        echo "  • Taille: $(df -h $BACKUP_ROOT | awk 'NR==2 {print $2}')"
        echo ""
        df -h "$BACKUP_ROOT"
    else
        log "ERROR" "Échec du montage du disque"
    fi
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

# ----------------------------------------------------------------------------
# EXERCICE 6.9 : ORGANISATION DES FICHIERS DE BACKUP
# ----------------------------------------------------------------------------
exercice_6_9() {
    print_header
    echo "EXERCICE 6.9: ORGANISATION DES FICHIERS DE BACKUP"
    echo "─────────────────────────────────────────────────"
    
    echo "Schéma d'organisation adopté:"
    echo ""
    echo "$BACKUP_ROOT/"
    echo "├── YYYYMMDD_HHMMSS_full/          # Sauvegarde complète"
    echo "│   ├── homes/                     # Homes utilisateurs"
    echo "│   ├── mysql/                     # Bases de données MySQL"
    echo "│   ├── ldap/                      # Données LDAP"
    echo "│   ├── wordpress/                 # Site WordPress"
    echo "│   ├── system/                    # Informations système"
    echo "│   ├── logs/                      # Logs de l'opération"
    echo "│   └── checksums.sha256           # Vérification d'intégrité"
    echo "├── YYYYMMDD_HHMMSS_incr/          # Sauvegarde incrémentale"
    echo "└── YYYYMMDD_HHMMSS_diff/          # Sauvegarde différentielle"
    echo ""
    
    echo "Caractéristiques:"
    echo "  • Un dossier par sauvegarde avec horodatage"
    echo "  • Séparation par type de données"
    echo "  • Checksums pour vérification"
    echo "  • Logs inclus dans chaque sauvegarde"
    echo "  • Rétention: $RETENTION_DAYS jours"
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

# ----------------------------------------------------------------------------
# SAUVEGARDE DES HOMES (Exercice 6.10)
# ----------------------------------------------------------------------------
backup_homes() {
    local backup_type=$1
    local backup_path=$2
    
    log "INFO" "Sauvegarde des homes utilisateurs (type: $backup_type)"
    
    local snapshot_file="$BACKUP_ROOT/homes_snapshot.sn"
    local tar_options="--create --preserve-permissions --xattrs --acls --selinux --numeric-owner --gzip"
    
    case $backup_type in
        "full")
            log "INFO" "Création d'une sauvegarde complète"
            
            # Si un snapshot existe, le sauvegarder
            if [ -f "$snapshot_file" ]; then
                cp "$snapshot_file" "$backup_path/homes/snapshot_backup.sn"
            fi
            
            # Créer une nouvelle sauvegarde complète
            tar $tar_options \
                --listed-incremental="$snapshot_file" \
                --file="$backup_path/homes/homes_full_$DATE.tar.gz" \
                --directory="/home" .
            
            # Marquer comme dernière sauvegarde complète
            echo "$backup_path" > "$BACKUP_ROOT/last_full.txt"
            ;;
            
        "incremental")
            log "INFO" "Création d'une sauvegarde incrémentale"
            
            # Vérifier qu'une sauvegarde complète existe
            if [ ! -f "$snapshot_file" ]; then
                log "WARNING" "Aucune sauvegarde complète trouvée, conversion en full"
                backup_homes "full" "$backup_path"
                return
            fi
            
            tar $tar_options \
                --listed-incremental="$snapshot_file" \
                --file="$backup_path/homes/homes_incr_$DATE.tar.gz" \
                --directory="/home" .
            ;;
            
        "differential")
            log "INFO" "Création d'une sauvegarde différentielle"
            
            # Copier le snapshot pour le différentiel
            local diff_snapshot="$BACKUP_ROOT/homes_snapshot_diff.sn"
            cp "$snapshot_file" "$diff_snapshot"
            
            tar $tar_options \
                --listed-incremental="$diff_snapshot" \
                --file="$backup_path/homes/homes_diff_$DATE.tar.gz" \
                --directory="/home" .
            
            rm -f "$diff_snapshot"
            ;;
    esac
    
    # Vérifier l'intégrité de l'archive
    local archive=$(ls -t "$backup_path/homes/"*.tar.gz 2>/dev/null | head -1)
    if [ -f "$archive" ]; then
        if tar -tzf "$archive" > /dev/null 2>&1; then
            log "SUCCESS" "Archive créée: $(basename $archive) ($(du -h $archive | cut -f1))"
        else
            log "ERROR" "Archive corrompue: $archive"
            return 1
        fi
    fi
    
    return 0
}

# ----------------------------------------------------------------------------
# SAUVEGARDE MYSQL (Exercice 6.12)
# ----------------------------------------------------------------------------
backup_mysql() {
    local backup_path=$1
    
    log "INFO" "Sauvegarde des bases de données MySQL"
    
    # Vérifier la connexion MySQL
    if ! mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" -e "SELECT 1" > /dev/null 2>&1; then
        log "ERROR" "Impossible de se connecter à MySQL"
        return 1
    fi
    
    # Obtenir la liste des bases de données (exclure les bases système)
    local databases=$(mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" \
        -e "SHOW DATABASES" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
    
    local total_size=0
    local db_count=0
    
    # Sauvegarde individuelle de chaque base
    for db in $databases; do
        log "INFO" "Sauvegarde de la base: $db"
        
        local dump_file="$backup_path/mysql/${db}_${DATE}.sql"
        
        # Utiliser --single-transaction pour la cohérence (Exercice 6.13)
        if mysqldump --user="$MYSQL_USER" \
                     --password="$MYSQL_PASS" \
                     --single-transaction \
                     --routines \
                     --triggers \
                     --events \
                     --hex-blob \
                     "$db" > "$dump_file" 2>> "$backup_path/logs/mysql.log"
        then
            # Compresser
            gzip "$dump_file"
            
            local size=$(du -k "${dump_file}.gz" | cut -f1)
            total_size=$((total_size + size))
            db_count=$((db_count + 1))
            
            log "SUCCESS" "  ✓ $db: $(echo "scale=1; $size/1024" | bc) MB"
        else
            log "ERROR" "  ✗ Échec de la sauvegarde de $db"
        fi
    done
    
    # Sauvegarde complète de toutes les bases
    log "INFO" "Sauvegarde de toutes les bases"
    mysqldump --user="$MYSQL_USER" \
              --password="$MYSQL_PASS" \
              --single-transaction \
              --routines \
              --triggers \
              --events \
              --all-databases | gzip > "$backup_path/mysql/all_databases_${DATE}.sql.gz"
    
    log "SUCCESS" "Sauvegarde MySQL terminée: $db_count bases, $(echo "scale=1; $total_size/1024" | bc) MB"
    return 0
}

# ----------------------------------------------------------------------------
# SAUVEGARDE LDAP (Exercice 6.15)
# ----------------------------------------------------------------------------
backup_ldap() {
    local backup_path=$1
    
    log "INFO" "Sauvegarde de la base LDAP"
    
    # Vérifier si le service LDAP est actif
    if ! systemctl is-active slapd > /dev/null 2>&1; then
        log "WARNING" "Le service LDAP n'est pas actif"
        return 1
    fi
    
    # Méthode 1: slapcat (recommandée)
    if command -v slapcat > /dev/null 2>&1; then
        log "INFO" "Utilisation de slapcat pour l'export"
        
        local ldif_file="$backup_path/ldap/ldap_full_${DATE}.ldif"
        
        if slapcat -v -l "$ldif_file" 2>> "$backup_path/logs/ldap.log"; then
            gzip "$ldif_file"
            log "SUCCESS" "Export LDAP réussi: $(du -h ${ldif_file}.gz | cut -f1)"
        else
            log "ERROR" "Échec de l'export avec slapcat"
            return 1
        fi
    else
        # Méthode 2: ldapsearch
        log "INFO" "Utilisation de ldapsearch pour l'export"
        
        local ldif_file="$backup_path/ldap/ldap_${DATE}.ldif"
        
        if ldapsearch -x -H ldap://localhost -b "dc=isty,dc=com" -D "$LDAP_ADMIN" \
            -w "$LDAP_PASS" > "$ldif_file" 2>> "$backup_path/logs/ldap.log"
        then
            gzip "$ldif_file"
            log "SUCCESS" "Export LDAP réussi"
        else
            log "ERROR" "Échec de l'export avec ldapsearch"
            return 1
        fi
    fi
    
    # Sauvegarder également la configuration
    if [ -d "/etc/openldap" ]; then
        tar -czf "$backup_path/ldap/ldap_config_${DATE}.tar.gz" -C /etc openldap
        log "INFO" "Configuration LDAP sauvegardée"
    fi
    
    return 0
}

# ----------------------------------------------------------------------------
# GENERATION DE CHECKSUMS (Exercice 6.16)
# ----------------------------------------------------------------------------
generate_checksums() {
    local backup_path=$1
    
    log "INFO" "Génération des checksums d'intégrité"
    
    # SHA256 pour tous les fichiers
    find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
        -exec sha256sum {} \; > "$backup_path/checksums.sha256"
    
    # MD5 supplémentaire
    find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
        -exec md5sum {} \; > "$backup_path/checksums.md5"
    
    # Vérifier les checksums
    if cd "$backup_path" && sha256sum -c "checksums.sha256" > /dev/null 2>&1; then
        log "SUCCESS" "Checksums vérifiés avec succès"
        return 0
    else
        log "ERROR" "Erreur dans les checksums"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.17 : CONFIGURATION CRON
# ----------------------------------------------------------------------------
exercice_6_17() {
    print_header
    echo "EXERCICE 6.17: CONFIGURATION DES TÂCHES CRON"
    echo "────────────────────────────────────────────"
    
    local cron_file="/etc/cron.d/tp6-backup"
    
    echo "Planification proposée:"
    echo ""
    echo "1. Sauvegarde complète   : Dimanche à 2h00"
    echo "2. Sauvegarde incrémentale : Lundi-Samedi à 2h00"
    echo "3. Sauvegarde différentielle : 1er du mois à 3h00"
    echo "4. Nettoyage             : Tous les jours à 4h00"
    echo "5. Vérification          : Vendredi à 5h00"
    echo ""
    
    read -p "Créer cette planification? (O/n): " choice
    
    if [[ "$choice" == "n" || "$choice" == "N" ]]; then
        return
    fi
    
    # Créer le fichier cron
    cat > "$cron_file" << EOF
# TP6 - Planification des sauvegardes
# Généré le $(date)

# Sauvegarde complète - Dimanche 2h00
0 2 * * 0 root /usr/local/bin/tp6_complet.sh --cron full

# Sauvegarde incrémentale - Lundi à Samedi 2h00
0 2 * * 1-6 root /usr/local/bin/tp6_complet.sh --cron incremental

# Sauvegarde différentielle - 1er du mois 3h00
0 3 1 * * root /usr/local/bin/tp6_complet.sh --cron differential

# Nettoyage des anciennes sauvegardes - Tous les jours 4h00
0 4 * * * root /usr/local/bin/tp6_complet.sh --cron cleanup

# Vérification d'intégrité - Vendredi 5h00
0 5 * * 5 root /usr/local/bin/tp6_complet.sh --cron verify

# Test de restauration - Premier dimanche du mois 6h00
0 6 * * 0 [ \$(date +\%d) -le 7 ] && /usr/local/bin/tp6_complet.sh --cron test-restore
EOF
    
    chmod 644 "$cron_file"
    
    log "SUCCESS" "Fichier cron créé: $cron_file"
    echo ""
    echo "Contenu du fichier:"
    echo "──────────────────"
    cat "$cron_file"
    
    echo ""
    echo "Pour activer immédiatement:"
    echo "  systemctl restart cronie"
    echo "  systemctl enable cronie"
    
    read -p "Redémarrer le service cron maintenant? (O/n): " choice
    if [[ "$choice" != "n" && "$choice" != "N" ]]; then
        systemctl restart cronie
        log "SUCCESS" "Service cron redémarré"
    fi
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

# ----------------------------------------------------------------------------
# FONCTION DE SAUVEGARDE PRINCIPALE
# ----------------------------------------------------------------------------
perform_backup() {
    local backup_type=$1
    
    print_header
    echo "LANCEMENT D'UNE SAUVEGARDE: $backup_type"
    echo "────────────────────────────────────────"
    
    # Vérifier que le point de montage existe
    if ! mountpoint -q "$BACKUP_ROOT" 2>/dev/null; then
        log "ERROR" "Le répertoire $BACKUP_ROOT n'est pas monté"
        echo "Utilisez l'option 1 pour configurer le disque de backup"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        return 1
    fi
    
    # Créer le répertoire de sauvegarde
    local backup_path="$BACKUP_ROOT/${DATE}_${backup_type}"
    mkdir -p "$backup_path"/{homes,mysql,ldap,wordpress,logs,system}
    
    log "INFO" "Début de la sauvegarde $backup_type"
    log "INFO" "Destination: $backup_path"
    
    # Sauvegarder les informations système
    save_system_info "$backup_path"
    
    # Exécuter les sauvegardes
    local errors=0
    
    echo ""
    echo "Progression:"
    echo "────────────"
    
    # 1. Sauvegarde des homes
    echo -n "1. Homes utilisateurs... "
    if backup_homes "$backup_type" "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # 2. Sauvegarde MySQL
    echo -n "2. Bases de données MySQL... "
    if backup_mysql "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # 3. Sauvegarde LDAP
    echo -n "3. Base LDAP... "
    if backup_ldap "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # 4. Sauvegarde WordPress
    echo -n "4. Site WordPress... "
    if backup_wordpress "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # 5. Génération des checksums
    echo -n "5. Vérification d'intégrité... "
    if generate_checksums "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # Créer un rapport
    create_backup_report "$backup_path" "$backup_type" "$errors"
    
    # Afficher le résumé
    echo ""
    echo "RÉSUMÉ DE LA SAUVEGARDE:"
    echo "────────────────────────"
    echo "Type: $backup_type"
    echo "Date: $(date)"
    echo "Destination: $backup_path"
    echo "Taille totale: $(du -sh $backup_path | cut -f1)"
    echo "Erreurs: $errors"
    echo ""
    
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "Sauvegarde $backup_type terminée avec succès"
    else
        log "WARNING" "Sauvegarde terminée avec $errors erreur(s)"
    fi
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
    return $errors
}

save_system_info() {
    local backup_path=$1
    
    # Informations système
    uname -a > "$backup_path/system/uname.txt"
    df -h > "$backup_path/system/disk_usage.txt"
    free -h > "$backup_path/system/memory.txt"
    ps aux > "$backup_path/system/processes.txt"
    
    # Liste des utilisateurs
    getent passwd > "$backup_path/system/users.txt"
    
    # Configuration réseau
    ip addr show > "$backup_path/system/network.txt"
}

backup_wordpress() {
    local backup_path=$1
    
    # Vérifier si WordPress est installé
    if [ ! -d "$WORDPRESS_DIR" ]; then
        log "WARNING" "Répertoire WordPress non trouvé: $WORDPRESS_DIR"
        return 1
    fi
    
    # Sauvegarder les fichiers WordPress
    tar -czf "$backup_path/wordpress/files_${DATE}.tar.gz" \
        -C "$(dirname $WORDPRESS_DIR)" \
        "$(basename $WORDPRESS_DIR)"
    
    # Sauvegarder la base WordPress si elle existe
    if mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" -e "USE wordpress" > /dev/null 2>&1; then
        mysqldump --user="$MYSQL_USER" \
                  --password="$MYSQL_PASS" \
                  --single-transaction \
                  wordpress | gzip > "$backup_path/wordpress/database_${DATE}.sql.gz"
    fi
    
    log "SUCCESS" "WordPress sauvegardé"
    return 0
}

create_backup_report() {
    local backup_path=$1
    local backup_type=$2
    local errors=$3
    
    cat > "$backup_path/backup_report.txt" << EOF
RAPPORT DE SAUVEGARDE TP6
=========================

Informations générales
──────────────────────
Date: $(date)
Type: $backup_type
Hôte: $(hostname)
Utilisateur: $(whoami)
Chemin: $backup_path

Statistiques
────────────
Date début: $(cat $backup_path/logs/start_time.txt 2>/dev/null || echo "N/A")
Date fin: $(date)
Taille: $(du -sh $backup_path | cut -f1)
Erreurs: $errors

Contenu
───────
$(find "$backup_path" -type f -name "*.gz" -o -name "*.tar" | xargs -I {} basename {} | sort)

Système
───────
$(uname -a)

Disque
──────
$(df -h $BACKUP_ROOT)

Vérification
────────────
$(if [ $errors -eq 0 ]; then echo "STATUS: ✓ SUCCÈS"; else echo "STATUS: ✗ ÉCHEC"; fi)

Instructions de restauration
───────────────────────────
Pour restaurer cette sauvegarde:
1. sudo $0 --restore $backup_path
2. Suivre les instructions à l'écran

EOF
}

# ----------------------------------------------------------------------------
# EXERCICE 6.18 : GÉNÉRATION DE BACKUPS DE TEST
# ----------------------------------------------------------------------------
exercice_6_18() {
    print_header
    echo "EXERCICE 6.18: GÉNÉRATION DE BACKUPS DE TEST"
    echo "────────────────────────────────────────────"
    
    echo "Cet exercice va générer:"
    echo "1. Un backup complet"
    echo "2. Un backup incrémental"
    echo ""
    
    read -p "Générer un backup complet maintenant? (O/n): " choice
    if [[ "$choice" != "n" && "$choice" != "N" ]]; then
        perform_backup "full"
    fi
    
    echo ""
    read -p "Générer un backup incrémental maintenant? (O/n): " choice
    if [[ "$choice" != "n" && "$choice" != "N" ]]; then
        # Créer un fichier de test pour l'incrémental
        touch /home/test_file_incr_$DATE.txt
        echo "Fichier de test pour backup incrémental" > /home/test_file_incr_$DATE.txt
        
        perform_backup "incremental"
        
        # Nettoyer le fichier de test
        rm -f /home/test_file_incr_$DATE.txt
    fi
    
    # Lister les sauvegardes créées
    echo ""
    echo "SAUVEGARDES DISPONIBLES:"
    echo "───────────────────────"
    list_backups
}

# ----------------------------------------------------------------------------
# EXERCICE 6.19 : TRANSFERT ET RESTAURATION
# ----------------------------------------------------------------------------
exercice_6_19() {
    print_header
    echo "EXERCICE 6.19: TRANSFERT ET RESTAURATION"
    echo "────────────────────────────────────────"
    
    echo "Cette fonction simule le transfert vers une nouvelle machine"
    echo "et la restauration complète des données."
    echo ""
    
    # Lister les sauvegardes disponibles
    echo "Sauvegardes disponibles:"
    echo "───────────────────────"
    list_backups_simple
    
    echo ""
    read -p "Entrez la date de la sauvegarde à restaurer (ex: 20240115_020000): " backup_date
    
    if [ -z "$backup_date" ]; then
        log "ERROR" "Date non spécifiée"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        return
    fi
    
    # Trouver la sauvegarde
    local backup_path=$(find "$BACKUP_ROOT" -type d -name "*${backup_date}*" | head -1)
    
    if [ -z "$backup_path" ] || [ ! -d "$backup_path" ]; then
        log "ERROR" "Sauvegarde non trouvée: $backup_date"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        return
    fi
    
    echo ""
    echo "Sauvegarde sélectionnée: $backup_path"
    echo "Taille: $(du -sh $backup_path | cut -f1)"
    echo ""
    
    # Menu de restauration
    echo "QUE VOULEZ-VOUS RESTAURER?"
    echo "──────────────────────────"
    echo "1. Tout restaurer (restauration complète)"
    echo "2. Uniquement les homes utilisateurs"
    echo "3. Uniquement les bases MySQL"
    echo "4. Uniquement la base LDAP"
    echo "5. Uniquement WordPress"
    echo "6. Annuler"
    echo ""
    
    read -p "Votre choix [1-6]: " choice
    
    case $choice in
        1)
            restore_all "$backup_path"
            ;;
        2)
            restore_homes_only "$backup_path"
            ;;
        3)
            restore_mysql_only "$backup_path"
            ;;
        4)
            restore_ldap_only "$backup_path"
            ;;
        5)
            restore_wordpress_only "$backup_path"
            ;;
        *)
            echo "Restauration annulée"
            ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

restore_all() {
    local backup_path=$1
    
    log "INFO" "Restauration complète depuis: $backup_path"
    
    # Vérifier les checksums d'abord
    if [ -f "$backup_path/checksums.sha256" ]; then
        echo "Vérification de l'intégrité..."
        if ! sha256sum -c "$backup_path/checksums.sha256" > /dev/null 2>&1; then
            log "ERROR" "La sauvegarde est corrompue!"
            return 1
        fi
    fi
    
    # Restaurer les homes
    restore_homes_only "$backup_path"
    
    # Restaurer MySQL
    restore_mysql_only "$backup_path"
    
    # Restaurer LDAP
    restore_ldap_only "$backup_path"
    
    # Restaurer WordPress
    restore_wordpress_only "$backup_path"
    
    log "SUCCESS" "Restauration complète terminée"
}

restore_homes_only() {
    local backup_path=$1
    
    log "INFO" "Restauration des homes utilisateurs"
    
    # Trouver la dernière sauvegarde complète des homes
    local home_backup=$(find "$backup_path/homes" -name "homes_full_*.tar.gz" | sort -r | head -1)
    
    if [ ! -f "$home_backup" ]; then
        log "ERROR" "Aucune sauvegarde de homes trouvée"
        return 1
    fi
    
    echo "Restauration depuis: $(basename $home_backup)"
    read -p "Confirmer la restauration des homes? (O/n): " confirm
    
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        return
    fi
    
    # Extraire
    tar -xzf "$home_backup" -C /
    
    log "SUCCESS" "Homes utilisateurs restaurés"
}

restore_mysql_only() {
    local backup_path=$1
    
    log "INFO" "Restauration des bases MySQL"
    
    # Trouver la sauvegarde complète
    local mysql_backup=$(find "$backup_path/mysql" -name "all_databases_*.sql.gz" | head -1)
    
    if [ ! -f "$mysql_backup" ]; then
        log "ERROR" "Aucune sauvegarde MySQL trouvée"
        return 1
    fi
    
    echo "Restauration depuis: $(basename $mysql_backup)"
    read -p "Confirmer la restauration MySQL? (O/n): " confirm
    
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        return
    fi
    
    # Restaurer
    gunzip -c "$mysql_backup" | mysql --user="$MYSQL_USER" --password="$MYSQL_PASS"
    
    log "SUCCESS" "Bases MySQL restaurées"
}

restore_ldap_only() {
    local backup_path=$1
    
    log "INFO" "Restauration de la base LDAP"
    
    local ldap_backup=$(find "$backup_path/ldap" -name "ldap_*.ldif.gz" | head -1)
    
    if [ ! -f "$ldap_backup" ]; then
        log "ERROR" "Aucune sauvegarde LDAP trouvée"
        return 1
    fi
    
    echo "Restauration depuis: $(basename $ldap_backup)"
    read -p "Confirmer la restauration LDAP? (O/n): " confirm
    
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        return
    fi
    
    # Arrêter le service LDAP
    systemctl stop slapd
    
    # Restaurer
    gunzip -c "$ldap_backup" | slapadd -v
    
    # Redémarrer
    systemctl start slapd
    
    log "SUCCESS" "Base LDAP restaurée"
}

restore_wordpress_only() {
    local backup_path=$1
    
    log "INFO" "Restauration de WordPress"
    
    local wp_backup=$(find "$backup_path/wordpress" -name "files_*.tar.gz" | head -1)
    
    if [ ! -f "$wp_backup" ]; then
        log "ERROR" "Aucune sauvegarde WordPress trouvée"
        return 1
    fi
    
    echo "Restauration depuis: $(basename $wp_backup)"
    read -p "Confirmer la restauration WordPress? (O/n): " confirm
    
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        return
    fi
    
    # Extraire
    tar -xzf "$wp_backup" -C /
    
    log "SUCCESS" "WordPress restauré"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.20 : RESTAURATION UTILISATEUR "raj"
# ----------------------------------------------------------------------------
exercice_6_20() {
    print_header
    echo "EXERCICE 6.20: RESTAURATION DE L'UTILISATEUR 'raj'"
    echo "──────────────────────────────────────────────────"
    
    echo "Scénario: L'utilisateur 'raj' a supprimé son dossier 'htop-dev'"
    echo "et souhaite le récupérer depuis les sauvegardes."
    echo ""
    
    # Vérifier si l'utilisateur existe
    if ! id "raj" > /dev/null 2>&1; then
        log "WARNING" "L'utilisateur 'raj' n'existe pas sur ce système"
        read -p "Créer l'utilisateur 'raj' maintenant? (O/n): " choice
        
        if [[ "$choice" != "n" && "$choice" != "N" ]]; then
            useradd -m raj
            echo "Utilisateur 'raj' créé"
        else
            return
        fi
    fi
    
    # Lister les sauvegardes disponibles
    echo ""
    echo "Recherche des sauvegardes contenant l'utilisateur 'raj'..."
    
    # Chercher dans les sauvegardes récentes
    local recent_backups=$(find "$BACKUP_ROOT" -type d -name "*_full" | sort -r | head -5)
    
    for backup in $recent_backups; do
        local home_backup=$(find "$backup/homes" -name "*.tar.gz" | head -1)
        
        if [ -f "$home_backup" ] && tar -tzf "$home_backup" | grep -q "^home/raj/"; then
            echo ""
            echo "✓ Sauvegarde trouvée: $(basename $backup)"
            echo "  Date: $(echo $backup | grep -o '[0-9]\{8\}_[0-9]\{6\}')"
            echo "  Fichier: $(basename $home_backup)"
            
            read -p "Restaurer le home de 'raj' depuis cette sauvegarde? (O/n): " choice
            
            if [[ "$choice" != "n" && "$choice" != "N" ]]; then
                restore_single_user "raj" "$home_backup"
                return
            fi
        fi
    done
    
    log "ERROR" "Aucune sauvegarde de l'utilisateur 'raj' trouvée"
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

restore_single_user() {
    local username=$1
    local backup_file=$2
    
    log "INFO" "Restauration de l'utilisateur: $username"
    
    # Sauvegarder les fichiers actuels
    local backup_dir="/home/${username}_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "/home/$username" ]; then
        echo "Sauvegarde des fichiers actuels vers: $backup_dir"
        cp -r "/home/$username" "$backup_dir"
    fi
    
    # Extraire seulement le répertoire de l'utilisateur
    echo "Extraction des fichiers depuis la sauvegarde..."
    
    # Créer le répertoire s'il n'existe pas
    mkdir -p "/home/$username"
    
    # Extraire
    tar -xzf "$backup_file" \
        --directory="/" \
        --preserve-permissions \
        "home/$username"
    
    # Ajuster les permissions
    chown -R "$username:$username" "/home/$username"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "RESTAURATION RÉUSSIE"
    echo "────────────────────"
    echo "Utilisateur: $username"
    echo "Source: $(basename $backup_file)"
    echo "Destination: /home/$username"
    echo "Sauvegarde précédente: $backup_dir"
    echo "═══════════════════════════════════════════════════"
    
    # Vérifier si le dossier htop-dev existe
    if [ -d "/home/$username/htop-dev" ]; then
        echo ""
        echo "✅ Le dossier 'htop-dev' a été restauré avec succès"
        ls -la "/home/$username/htop-dev/"
    else
        echo ""
        echo "⚠ Le dossier 'htop-dev' n'a pas été trouvé dans la sauvegarde"
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.21 BONUS : LVM SNAPSHOTS
# ----------------------------------------------------------------------------
exercice_6_21() {
    print_header
    echo "EXERCICE 6.21 BONUS: UTILISATION DE LVM POUR LES SNAPSHOTS"
    echo "──────────────────────────────────────────────────────────"
    
    echo "Cette fonction utilise LVM pour créer des snapshots cohérents"
    echo "des homes utilisateurs pendant les sauvegardes."
    echo ""
    
    # Vérifier si LVM est disponible
    if ! command -v lvcreate > /dev/null 2>&1; then
        log "ERROR" "LVM n'est pas installé"
        echo "Installer LVM avec: emerge -av sys-fs/lvm2"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        return
    fi
    
    # Chercher un volume logique contenant /home
    local home_lv=$(df /home 2>/dev/null | awk 'NR==2 {print $1}')
    
    if [[ ! $home_lv =~ /dev/mapper/ ]]; then
        log "ERROR" "/home n'est pas sur un volume LVM"
        echo "Configuration LVM requise pour cette fonctionnalité"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        return
    fi
    
    # Extraire les informations LVM
    local vg_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f1)
    local lv_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f2)
    
    echo "Configuration LVM détectée:"
    echo "  Volume Group: $vg_name"
    echo "  Logical Volume: $lv_name"
    echo "  Chemin: $home_lv"
    echo ""
    
    echo "Options disponibles:"
    echo "───────────────────"
    echo "1. Créer un snapshot manuel"
    echo "2. Configurer les snapshots automatiques"
    echo "3. Lister les snapshots existants"
    echo "4. Supprimer un snapshot"
    echo "5. Retour"
    echo ""
    
    read -p "Votre choix [1-5]: " choice
    
    case $choice in
        1)
            create_lvm_snapshot_manual "$vg_name" "$lv_name"
            ;;
        2)
            configure_lvm_auto_snapshots "$vg_name" "$lv_name"
            ;;
        3)
            list_lvm_snapshots "$vg_name"
            ;;
        4)
            delete_lvm_snapshot "$vg_name"
            ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

create_lvm_snapshot_manual() {
    local vg=$1
    local lv=$2
    
    local snapshot_name="${lv}_snapshot_$(date +%Y%m%d_%H%M%S)"
    local snapshot_size="5G"
    
    echo "Création du snapshot: $snapshot_name"
    echo "Taille: $snapshot_size"
    echo ""
    
    read -p "Confirmer la création? (O/n): " choice
    
    if [[ "$choice" == "n" || "$choice" == "N" ]]; then
        return
    fi
    
    if lvcreate --snapshot \
                --name "$snapshot_name" \
                --size "$snapshot_size" \
                "/dev/$vg/$lv"; then
        log "SUCCESS" "Snapshot créé: $snapshot_name"
        
        # Monter le snapshot
        local mount_point="/mnt/snapshot_$snapshot_name"
        mkdir -p "$mount_point"
        
        if mount -o ro "/dev/$vg/$snapshot_name" "$mount_point"; then
            echo ""
            echo "Snapshot monté sur: $mount_point"
            echo "Contenu:"
            ls -la "$mount_point/"
            echo ""
            read -p "Démonter le snapshot? (O/n): " unmount_choice
            
            if [[ "$unmount_choice" != "n" && "$unmount_choice" != "N" ]]; then
                umount "$mount_point"
                rmdir "$mount_point"
                log "INFO" "Snapshot démonté"
            fi
        fi
    else
        log "ERROR" "Échec de la création du snapshot"
    fi
}

# ----------------------------------------------------------------------------
# FONCTIONS UTILITAIRES
# ----------------------------------------------------------------------------
list_backups() {
    echo "SAUVEGARDES DISPONIBLES:"
    echo "───────────────────────"
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "Aucune sauvegarde trouvée"
        return
    fi
    
    local backups=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | sort -r)
    
    if [ -z "$backups" ]; then
        echo "Aucune sauvegarde disponible"
        return
    fi
    
    printf "%-12s %-19s %-10s %s\n" "TYPE" "DATE" "TAILLE" "CHEMIN"
    echo "─────────────────────────────────────────────────────────────────────────"
    
    for backup in $backups; do
        local type=$(basename "$backup" | cut -d_ -f2)
        local date=$(basename "$backup" | cut -d_ -f1)
        local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        printf "%-12s %-19s %-10s %s\n" "$type" "$date" "$size" "$backup"
    done
}

list_backups_simple() {
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | sort -r | while read backup; do
        local name=$(basename "$backup")
        local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        echo "  $name - $size"
    done
}

cleanup_old_backups() {
    print_header
    echo "NETTOYAGE DES ANCIENNES SAUVEGARDES"
    echo "───────────────────────────────────"
    
    echo "Suppression des sauvegardes de plus de $RETENTION_DAYS jours..."
    echo ""
    
    local count=0
    local freed_space=0
    
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | while read backup; do
        local backup_date=$(basename "$backup" | cut -d_ -f1)
        
        # Convertir la date en format epoch
        local backup_epoch=$(date -d "${backup_date:0:4}-${backup_date:4:2}-${backup_date:6:2}" +%s 2>/dev/null)
        local current_epoch=$(date +%s)
        local age_days=$(( (current_epoch - backup_epoch) / 86400 ))
        
        if [ $age_days -gt $RETENTION_DAYS ]; then
            local size=$(du -sk "$backup" 2>/dev/null | cut -f1)
            echo "  Suppression: $(basename $backup) (âge: $age_days jours, taille: $(echo "scale=1; $size/1024" | bc) MB)"
            rm -rf "$backup"
            count=$((count + 1))
            freed_space=$((freed_space + size))
        fi
    done
    
    echo ""
    echo "RÉSUMÉ DU NETTOYAGE:"
    echo "  Sauvegardes supprimées: $count"
    echo "  Espace libéré: $(echo "scale=1; $freed_space/1024" | bc) MB"
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

verify_system() {
    print_header
    echo "VÉRIFICATION DU SYSTÈME DE BACKUP"
    echo "─────────────────────────────────"
    
    local errors=0
    
    echo "1. Vérification du point de montage..."
    if mountpoint -q "$BACKUP_ROOT"; then
        echo "   ✓ $BACKUP_ROOT est monté"
        echo "     Espace disponible: $(df -h $BACKUP_ROOT | awk 'NR==2 {print $4}')"
    else
        echo "   ✗ $BACKUP_ROOT n'est pas monté"
        errors=$((errors + 1))
    fi
    
    echo ""
    echo "2. Vérification des permissions..."
    local perms=$(stat -c "%a" "$BACKUP_ROOT" 2>/dev/null)
    if [ "$perms" = "750" ] || [ "$perms" = "700" ]; then
        echo "   ✓ Permissions sécurisées: $perms"
    else
        echo "   ⚠ Permissions non optimales: $perms"
    fi
    
    echo ""
    echo "3. Vérification des dépendances..."
    local deps=("tar" "gzip" "mysqldump" "ldapsearch" "sha256sum")
    for dep in "${deps[@]}"; do
        if command -v "$dep" > /dev/null 2>&1; then
            echo "   ✓ $dep disponible"
        else
            echo "   ✗ $dep manquant"
            errors=$((errors + 1))
        fi
    done
    
    echo ""
    echo "4. Vérification des services..."
    if systemctl is-active mysql > /dev/null 2>&1 || systemctl is-active mariadb > /dev/null 2>&1; then
        echo "   ✓ MySQL/MariaDB actif"
    else
        echo "   ⚠ MySQL/MariaDB inactif"
    fi
    
    if systemctl is-active slapd > /dev/null 2>&1; then
        echo "   ✓ LDAP actif"
    else
        echo "   ⚠ LDAP inactif"
    fi
    
    echo ""
    echo "5. Vérification des sauvegardes..."
    local backup_count=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" 2>/dev/null | wc -l)
    if [ $backup_count -gt 0 ]; then
        echo "   ✓ $backup_count sauvegarde(s) disponible(s)"
        
        # Vérifier la dernière sauvegarde
        local last_backup=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | sort -r | head -1)
        if [ -d "$last_backup" ]; then
            local checksum_file="$last_backup/checksums.sha256"
            if [ -f "$checksum_file" ]; then
                if sha256sum -c "$checksum_file" > /dev/null 2>&1; then
                    echo "   ✓ Dernière sauvegarde vérifiée: $(basename $last_backup)"
                else
                    echo "   ✗ Dernière sauvegarde corrompue: $(basename $last_backup)"
                    errors=$((errors + 1))
                fi
            fi
        fi
    else
        echo "   ⚠ Aucune sauvegarde disponible"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    if [ $errors -eq 0 ]; then
        echo "✅ SYSTÈME DE BACKUP EN BON ÉTAT"
    else
        echo "⚠ SYSTÈME DE BACKUP AVEC $errors ERREUR(S)"
    fi
    echo "═══════════════════════════════════════════════════"
    
    read -p "Appuyez sur Entrée pour continuer..." dummy
}

# ----------------------------------------------------------------------------
# MENU PRINCIPAL
# ----------------------------------------------------------------------------
show_main_menu() {
    while true; do
        print_header
        print_menu
        
        echo "CONFIGURATION:"
        echo "  1. Exercice 6.6-6.7 - Configurer le disque de backup"
        echo "  2. Exercice 6.9 - Voir l'organisation des backups"
        echo "  3. Exercice 6.17 - Configurer les tâches cron"
        echo ""
        
        echo "SAUVEGARDES:"
        echo "  4. Exercice 6.18 - Générer des backups de test"
        echo "  5. Sauvegarde complète (full)"
        echo "  6. Sauvegarde incrémentale (incremental)"
        echo "  7. Sauvegarde différentielle (differential)"
        echo ""
        
        echo "RESTAURATION:"
        echo "  8. Exercice 6.19 - Transfert et restauration complète"
        echo "  9. Exercice 6.20 - Restaurer l'utilisateur 'raj'"
        echo ""
        
        echo "ADMINISTRATION:"
        echo "  10. Exercice 6.21 Bonus - Gestion LVM Snapshots"
        echo "  11. Lister les sauvegardes disponibles"
        echo "  12. Nettoyer les anciennes sauvegardes"
        echo "  13. Vérifier l'état du système"
        echo "  14. Afficher les logs"
        echo ""
        
        echo "  0. Quitter"
        echo ""
        
        read -p "Votre choix [0-14]: " choice
        
        case $choice in
            1) exercice_6_6_7 ;;
            2) exercice_6_9 ;;
            3) exercice_6_17 ;;
            4) exercice_6_18 ;;
            5) perform_backup "full" ;;
            6) perform_backup "incremental" ;;
            7) perform_backup "differential" ;;
            8) exercice_6_19 ;;
            9) exercice_6_20 ;;
            10) exercice_6_21 ;;
            11) 
                print_header
                list_backups
                read -p "Appuyez sur Entrée pour continuer..." dummy
                ;;
            12) cleanup_old_backups ;;
            13) verify_system ;;
            14) 
                print_header
                echo "LOGS DISPONIBLES:"
                echo "────────────────"
                ls -la "$LOG_DIR/"*.log 2>/dev/null || echo "Aucun log disponible"
                echo ""
                read -p "Nom du fichier log (sans chemin): " logfile
                if [ -f "$LOG_DIR/$logfile" ]; then
                    echo ""
                    echo "Contenu de $logfile:"
                    echo "────────────────────"
                    tail -50 "$LOG_DIR/$logfile"
                fi
                read -p "Appuyez sur Entrée pour continuer..." dummy
                ;;
            0)
                echo ""
                echo "Merci d'avoir utilisé le script TP6 de sauvegarde!"
                echo ""
                exit 0
                ;;
            *)
                echo "Choix invalide"
                sleep 1
                ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# MODE CRON (exécution non-interactive)
# ----------------------------------------------------------------------------
cron_mode() {
    local action=$1
    
    case $action in
        "full")
            perform_backup "full"
            ;;
        "incremental")
            perform_backup "incremental"
            ;;
        "differential")
            perform_backup "differential"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "verify")
            verify_system
            ;;
        "test-restore")
            echo "Test de restauration cron - non implémenté en mode automatique"
            ;;
    esac
}

# ----------------------------------------------------------------------------
# MODE RESTAURATION RAPIDE
# ----------------------------------------------------------------------------
restore_mode() {
    local backup_path=$1
    
    if [ ! -d "$backup_path" ]; then
        echo "ERREUR: Le chemin de sauvegarde n'existe pas: $backup_path"
        exit 1
    fi
    
    echo "Mode restauration rapide activé"
    echo "Sauvegarde: $backup_path"
    echo ""
    
    restore_all "$backup_path"
}

# ----------------------------------------------------------------------------
# POINT D'ENTRÉE PRINCIPAL
# ----------------------------------------------------------------------------
main() {
    # Créer le répertoire de logs
    mkdir -p "$LOG_DIR"
    
    # Mode d'exécution
    case "$1" in
        "--cron")
            # Mode non-interactif pour cron
            cron_mode "$2"
            ;;
        "--restore")
            # Mode restauration rapide
            restore_mode "$2"
            ;;
        "--help"|"-h")
            print_header
            echo "UTILISATION:"
            echo "  $0                    # Mode interactif avec menu"
            echo "  $0 --cron <action>   # Mode cron (full|incremental|differential|cleanup|verify)"
            echo "  $0 --restore <path>  # Restauration rapide depuis le chemin spécifié"
            echo "  $0 --help            # Afficher cette aide"
            echo ""
            echo "EXEMPLES:"
            echo "  $0                           # Lancer le menu interactif"
            echo "  $0 --cron full               # Exécuter une sauvegarde complète"
            echo "  $0 --restore /mnt/backup/20240115_020000_full"
            echo ""
            exit 0
            ;;
        *)
            # Mode interactif par défaut
            init_system
            show_main_menu
            ;;
    esac
}

# ----------------------------------------------------------------------------
# GESTION DES SIGNALS
# ----------------------------------------------------------------------------
trap 'echo ""; echo "Interruption reçue. Arrêt en cours..."; exit 1' INT TERM

# ----------------------------------------------------------------------------
# LANCER LE SCRIPT
# ----------------------------------------------------------------------------
main "$@"