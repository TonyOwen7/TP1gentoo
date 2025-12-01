#!/bin/bash
# ============================================================================
# TP6 COMPLET - SAUVEGARDE ET RESTAURATION
# Version adaptée pour Gentoo avec gestion des erreurs de dépendances
# ============================================================================

set -e  # Arrêter en cas d'erreur

# ----------------------------------------------------------------------------
# CONFIGURATION GLOBALE
# ----------------------------------------------------------------------------
readonly VERSION="TP6-Gentoo-v2.1"
readonly CONFIG_FILE="/etc/tp6_backup.conf"
readonly BACKUP_ROOT="/mnt/backup"
readonly LOG_DIR="/var/log/backup"
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
# FONCTIONS D'AFFICHAGE
# ----------------------------------------------------------------------------
print_header() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              TP6 - SAUVEGARDE ET RESTAURATION                ║"
    echo "║                     Système Gentoo                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

print_section() {
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOG_DIR/tp6_$(date +%Y%m).log"
    
    mkdir -p "$LOG_DIR"
    
    case $level in
        "SUCCESS") echo -e "\e[32m[$timestamp] ✓ $message\e[0m" ;;
        "INFO") echo -e "\e[34m[$timestamp] ℹ $message\e[0m" ;;
        "WARNING") echo -e "\e[33m[$timestamp] ⚠ $message\e[0m" ;;
        "ERROR") echo -e "\e[31m[$timestamp] ✗ $message\e[0m" ;;
        *) echo "[$timestamp] $message" ;;
    esac
    
    echo "[$timestamp] $level: $message" >> "$log_file"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.6-6.7 : CONFIGURATION DU DISQUE
# ----------------------------------------------------------------------------
configure_disk() {
    print_header
    print_section "EXERCICE 6.6-6.7 : CONFIGURATION DU DISQUE DE BACKUP"
    
    echo "Cette fonction configure un disque supplémentaire pour les sauvegardes."
    echo ""
    
    # Afficher les disques disponibles
    echo "Disques détectés :"
    echo "────────────────"
    lsblk
    echo ""
    
    read -p "Voulez-vous configurer un disque pour les sauvegardes ? (o/N) : " choice
    if [[ "$choice" != "o" && "$choice" != "O" ]]; then
        return
    fi
    
    echo ""
    echo "Instructions pour VirtualBox/VMware :"
    echo "1. Arrêtez la VM"
    echo "2. Ajoutez un nouveau disque dur"
    echo "3. Redémarrez la VM"
    echo "4. Exécutez à nouveau cette option"
    echo ""
    echo "Le disque sera automatiquement détecté et configuré."
    
    # Vérifier les nouveaux disques
    local new_disk=""
    for disk in /dev/sd[b-z]; do
        if [ -b "$disk" ] && ! lsblk "$disk" | grep -q "part"; then
            new_disk="$disk"
            break
        fi
    done
    
    if [ -z "$new_disk" ]; then
        log "ERROR" "Aucun disque vierge détecté"
        echo "Veuillez ajouter un disque dans votre virtualiseur."
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi
    
    echo ""
    echo "Configuration de $new_disk..."
    
    # Partitionner
    echo "Création de la partition..."
    echo -e "n\np\n1\n\n\nw" | fdisk "$new_disk" > /dev/null 2>&1
    
    local partition="${new_disk}1"
    sleep 2
    
    # Formater
    echo "Formatage en ext4..."
    mkfs.ext4 -L "BACKUP_TP6" "$partition" > /dev/null 2>&1
    
    # Configurer le montage
    echo "Configuration du montage..."
    mkdir -p "$BACKUP_ROOT"
    echo "LABEL=BACKUP_TP6 $BACKUP_ROOT ext4 defaults,noatime 0 2" >> /etc/fstab
    
    # Monter
    mount "$BACKUP_ROOT"
    
    # Vérifier
    if mountpoint -q "$BACKUP_ROOT"; then
        log "SUCCESS" "Disque configuré avec succès"
        echo ""
        echo "Résumé :"
        echo "• Disque : $new_disk"
        echo "• Partition : $partition"
        echo "• Point de montage : $BACKUP_ROOT"
        echo "• Taille : $(df -h $BACKUP_ROOT | awk 'NR==2 {print $2}')"
        echo "• Utilisation : $(df -h $BACKUP_ROOT | awk 'NR==2 {print $5}')"
    else
        log "ERROR" "Échec du montage"
    fi
    
    read -p "Appuyez sur Entrée pour continuer..."
}

# ----------------------------------------------------------------------------
# EXERCICE 6.1-6.5 : THÉORIE ET PLANIFICATION
# ----------------------------------------------------------------------------
show_theory() {
    print_header
    print_section "EXERCICES 6.1-6.5 : THÉORIE ET PLANIFICATION"
    
    echo "1. SAUVEGARDE INCRÉMENTALE (Exercice 6.1)"
    echo "─────────────────────────────────────────"
    echo "Une sauvegarde incrémentale ne sauvegarde que les données modifiées"
    echo "depuis la dernière sauvegarde (complète ou incrémentale)."
    echo "Avantages : Rapide, peu d'espace utilisé"
    echo "Inconvénients : Restauration complexe (nécessite la chaîne complète)"
    echo ""
    
    echo "2. PLANNING DE SAUVEGARDE (Exercice 6.2)"
    echo "────────────────────────────────────────"
    echo "Notre stratégie :"
    echo "• Dimanche 02:00 : Sauvegarde complète"
    echo "• Lundi-Samedi 02:00 : Sauvegarde incrémentale"
    echo "• 1er du mois 03:00 : Sauvegarde différentielle"
    echo "Justification : Heures de faible activité, maintenance hebdomadaire"
    echo ""
    
    echo "3. CONTENUS À SAUVEGARDER (Exercice 6.3)"
    echo "────────────────────────────────────────"
    echo "• /home/* : 10-50 GB (homes utilisateurs)"
    echo "• Bases MySQL : 5-20 GB"
    echo "• LDAP : 1-5 GB"
    echo "• WordPress : 2-10 GB"
    echo ""
    
    echo "4. SUPPORTS DE SAUVEGARDE (Exercice 6.4)"
    echo "────────────────────────────────────────"
    echo "• Disque dur : Rapide, capacité ↑, coût modéré"
    echo "• SSD : Très rapide, durable, coût élevé"
    echo "• Bande : Faible coût/GB, durable, lent"
    echo "• Cloud : Accès distant, coût récurrent, dépendance réseau"
    echo ""
    
    echo "5. STOCKAGE DES SUPPORTS (Exercice 6.5)"
    echo "───────────────────────────────────────"
    echo "1. Localisation hors site"
    echo "2. Contrôle d'accès strict"
    echo "3. Conditions environnementales contrôlées"
    echo "4. Rotation régulière"
    echo "5. Tests de restauration périodiques"
    echo ""
    
    echo "6. CRITIQUE DU STOCKAGE DISQUE (Exercice 6.8)"
    echo "─────────────────────────────────────────────"
    echo "Avantages : Simple, rapide, économique"
    echo "Inconvénients : Vulnérable aux pannes, pas de protection hors site"
    echo "Amélioration : Ajouter une copie sur bande/cloud"
    echo ""
    
    read -p "Appuyez sur Entrée pour continuer..."
}

# ----------------------------------------------------------------------------
# INSTALLATION DES DÉPENDANCES (Gentoo spécifique)
# ----------------------------------------------------------------------------
install_dependencies() {
    print_header
    print_section "INSTALLATION DES DÉPENDANCES"
    
    echo "Cette fonction installe tous les paquets nécessaires pour le TP6."
    echo "Sur Gentoo, cela peut prendre un certain temps."
    echo ""
    
    read -p "Voulez-vous installer les dépendances ? (o/N) : " choice
    if [[ "$choice" != "o" && "$choice" != "O" ]]; then
        return
    fi
    
    log "INFO" "Mise à jour du système..."
    emerge --sync
    emerge --update --deep --with-bdeps=y @world
    
    echo ""
    echo "Installation des paquets de base..."
    echo "───────────────────────────────────"
    
    # Paquets essentiels sans problèmes de dépendances
    local basic_packages=(
        "app-arch/tar"
        "app-arch/gzip"
        "app-arch/bzip2"
        "app-arch/pigz"
        "sys-fs/lvm2"
        "net-misc/rsync"
        "app-crypt/gnupg"
        "mail-client/mailx"
        "sys-process/cronie"
        "net-nds/openldap"
    )
    
    for pkg in "${basic_packages[@]}"; do
        echo "Installation de $pkg..."
        emerge -av "$pkg" --autounmask-continue
    done
    
    echo ""
    echo "Gestion de MySQL/MariaDB..."
    echo "───────────────────────────"
    
    # Essayer MySQL d'abord (moins de problèmes de dépendances)
    echo "1. Essai d'installation de MySQL..."
    if emerge -av dev-db/mysql --autounmask-continue; then
        log "SUCCESS" "MySQL installé avec succès"
        MYSQL_TYPE="mysql"
    else
        echo ""
        echo "2. Échec de MySQL, essai de MariaDB sans Perl..."
        echo "   (Solution au problème dev-perl/DBD-MariaDB)"
        
        # Désactiver Perl pour MariaDB
        echo "dev-db/mariadb -perl" >> /etc/portage/package.use/backup-tp6
        
        if emerge -av dev-db/mariadb --autounmask-continue; then
            log "SUCCESS" "MariaDB installé sans support Perl"
            MYSQL_TYPE="mariadb"
        else
            echo ""
            echo "3. Installation minimale du client MySQL..."
            echo "   (Pour se connecter à un serveur existant)"
            emerge -av dev-db/mysql-connector-c --autounmask-continue
            MYSQL_TYPE="client-only"
            log "WARNING" "Seul le client MySQL est installé"
        fi
    fi
    
    echo ""
    echo "Configuration des services..."
    echo "────────────────────────────"
    
    # Activer les services
    rc-update add cronie default
    rc-update add slapd default
    
    if [ "$MYSQL_TYPE" = "mysql" ]; then
        rc-update add mysql default
    elif [ "$MYSQL_TYPE" = "mariadb" ]; then
        rc-update add mariadb default
    fi
    
    echo ""
    echo "Création de l'utilisateur de backup..."
    echo "──────────────────────────────────────"
    useradd -m -s /bin/bash -G wheel backup
    echo "backup:$(date +%s | sha256sum | base64 | head -c 16)" | chpasswd
    
    log "SUCCESS" "Installation des dépendances terminée"
    echo ""
    echo "Résumé :"
    echo "• MySQL/MariaDB : $MYSQL_TYPE"
    echo "• Services activés : cronie, slapd, $MYSQL_TYPE"
    echo "• Utilisateur : backup (mot de passe généré)"
    
    read -p "Appuyez sur Entrée pour continuer..."
}

# ----------------------------------------------------------------------------
# EXERCICE 6.9 : ORGANISATION DES BACKUPS
# ----------------------------------------------------------------------------
show_organization() {
    print_header
    print_section "EXERCICE 6.9 : ORGANISATION DES FICHIERS DE BACKUP"
    
    echo "Structure adoptée :"
    echo ""
    echo "$BACKUP_ROOT/"
    echo "├── YYYYMMDD_HHMMSS_full/"
    echo "│   ├── homes/          # Homes utilisateurs"
    echo "│   ├── mysql/          # Bases MySQL"
    echo "│   ├── ldap/           # Données LDAP"
    echo "│   ├── wordpress/      # WordPress"
    echo "│   ├── system/         # Informations système"
    echo "│   ├── logs/           # Logs de l'opération"
    echo "│   └── checksums.sha256"
    echo "├── YYYYMMDD_HHMMSS_incr/"
    echo "└── YYYYMMDD_HHMMSS_diff/"
    echo ""
    
    echo "Caractéristiques :"
    echo "• Un dossier par sauvegarde avec horodatage"
    echo "• Séparation par type de données"
    echo "• Checksums pour vérification d'intégrité"
    echo "• Logs inclus dans chaque sauvegarde"
    echo "• Rétention : $RETENTION_DAYS jours"
    echo ""
    
    echo "Avantages :"
    echo "• Organisation claire et logique"
    echo "• Facilité de restauration"
    echo "• Traçabilité complète"
    echo "• Gestion simplifiée de la rotation"
    
    read -p "Appuyez sur Entrée pour continuer..."
}

# ----------------------------------------------------------------------------
# SAUVEGARDE DES HOMES (Exercice 6.10)
# ----------------------------------------------------------------------------
backup_homes() {
    local backup_type=$1
    local backup_path=$2
    
    log "INFO" "Sauvegarde des homes (type: $backup_type)"
    
    local snapshot_file="$BACKUP_ROOT/homes_snapshot.sn"
    local tar_options="--create --preserve-permissions --xattrs --acls --selinux --numeric-owner --gzip"
    
    case $backup_type in
        "full")
            log "INFO" "Création sauvegarde complète"
            tar $tar_options \
                --listed-incremental="$snapshot_file" \
                --file="$backup_path/homes/homes_full_$DATE.tar.gz" \
                --directory="/home" .
            echo "$backup_path" > "$BACKUP_ROOT/last_full.txt"
            ;;
            
        "incremental")
            if [ ! -f "$snapshot_file" ]; then
                log "WARNING" "Pas de snapshot, conversion en full"
                backup_homes "full" "$backup_path"
                return
            fi
            
            log "INFO" "Création sauvegarde incrémentale"
            tar $tar_options \
                --listed-incremental="$snapshot_file" \
                --file="$backup_path/homes/homes_incr_$DATE.tar.gz" \
                --directory="/home" .
            ;;
            
        "differential")
            local diff_snapshot="$BACKUP_ROOT/homes_snapshot_diff.sn"
            cp "$snapshot_file" "$diff_snapshot"
            
            log "INFO" "Création sauvegarde différentielle"
            tar $tar_options \
                --listed-incremental="$diff_snapshot" \
                --file="$backup_path/homes/homes_diff_$DATE.tar.gz" \
                --directory="/home" .
            
            rm -f "$diff_snapshot"
            ;;
    esac
    
    # Vérification
    local archive=$(ls -t "$backup_path/homes/"*.tar.gz 2>/dev/null | head -1)
    if [ -f "$archive" ] && tar -tzf "$archive" > /dev/null 2>&1; then
        log "SUCCESS" "Archive créée : $(basename $archive) ($(du -h $archive | cut -f1))"
        return 0
    else
        log "ERROR" "Archive corrompue"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# SAUVEGARDE MYSQL (Exercice 6.12)
# ----------------------------------------------------------------------------
backup_mysql() {
    local backup_path=$1
    
    log "INFO" "Sauvegarde des bases MySQL"
    
    # Tester la connexion
    if ! mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" -e "SELECT 1" > /dev/null 2>&1; then
        log "ERROR" "Connexion MySQL impossible"
        return 1
    fi
    
    # Liste des bases (exclure les bases système)
    local databases=$(mysql --user="$MYSQL_USER" --password="$MYSQL_PASS" \
        -e "SHOW DATABASES" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
    
    local total_size=0
    local db_count=0
    
    for db in $databases; do
        log "INFO" "Sauvegarde de $db"
        local dump_file="$backup_path/mysql/${db}_${DATE}.sql"
        
        # --single-transaction pour la cohérence (Exercice 6.13)
        if mysqldump --user="$MYSQL_USER" \
                     --password="$MYSQL_PASS" \
                     --single-transaction \
                     --routines \
                     --triggers \
                     --events \
                     "$db" > "$dump_file" 2>> "$backup_path/logs/mysql.log"
        then
            gzip "$dump_file"
            local size=$(du -k "${dump_file}.gz" | cut -f1)
            total_size=$((total_size + size))
            db_count=$((db_count + 1))
            log "SUCCESS" "  ✓ $db : $(echo "scale=1; $size/1024" | bc) MB"
        else
            log "ERROR" "  ✗ Échec $db"
        fi
    done
    
    # Sauvegarde complète
    log "INFO" "Sauvegarde de toutes les bases"
    mysqldump --user="$MYSQL_USER" \
              --password="$MYSQL_PASS" \
              --single-transaction \
              --routines \
              --triggers \
              --events \
              --all-databases | gzip > "$backup_path/mysql/all_databases_${DATE}.sql.gz"
    
    log "SUCCESS" "Sauvegarde MySQL : $db_count bases, $(echo "scale=1; $total_size/1024" | bc) MB"
    return 0
}

# ----------------------------------------------------------------------------
# SAUVEGARDE LDAP (Exercice 6.15)
# ----------------------------------------------------------------------------
backup_ldap() {
    local backup_path=$1
    
    log "INFO" "Sauvegarde LDAP"
    
    # Vérifier le service
    if ! /etc/init.d/slapd status > /dev/null 2>&1; then
        log "WARNING" "Service LDAP inactif"
        return 1
    fi
    
    # Méthode slapcat
    if command -v slapcat > /dev/null 2>&1; then
        local ldif_file="$backup_path/ldap/ldap_${DATE}.ldif"
        
        if slapcat -v -l "$ldif_file" 2>> "$backup_path/logs/ldap.log"; then
            gzip "$ldif_file"
            log "SUCCESS" "LDAP exporté : $(du -h ${ldif_file}.gz | cut -f1)"
        else
            log "ERROR" "Échec slapcat"
            return 1
        fi
    else
        # Méthode ldapsearch
        local ldif_file="$backup_path/ldap/ldap_${DATE}.ldif"
        
        if ldapsearch -x -H ldap://localhost -b "dc=isty,dc=com" \
            -D "$LDAP_ADMIN" -w "$LDAP_PASS" > "$ldif_file" 2>> "$backup_path/logs/ldap.log"
        then
            gzip "$ldif_file"
            log "SUCCESS" "LDAP exporté via ldapsearch"
        else
            log "ERROR" "Échec ldapsearch"
            return 1
        fi
    fi
    
    # Configuration
    if [ -d "/etc/openldap" ]; then
        tar -czf "$backup_path/ldap/ldap_config_${DATE}.tar.gz" -C /etc openldap
        log "INFO" "Configuration LDAP sauvegardée"
    fi
    
    return 0
}

# ----------------------------------------------------------------------------
# GÉNÉRATION CHECKSUMS (Exercice 6.16)
# ----------------------------------------------------------------------------
generate_checksums() {
    local backup_path=$1
    
    log "INFO" "Génération des checksums"
    
    # SHA256
    find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
        -exec sha256sum {} \; > "$backup_path/checksums.sha256"
    
    # Vérification
    if cd "$backup_path" && sha256sum -c "checksums.sha256" > /dev/null 2>&1; then
        log "SUCCESS" "Checksums vérifiés"
        
        # MD5 additionnel
        find "$backup_path" -type f \( -name "*.gz" -o -name "*.tar" -o -name "*.sql" -o -name "*.ldif" \) \
            -exec md5sum {} \; > "$backup_path/checksums.md5"
            
        return 0
    else
        log "ERROR" "Erreur checksums"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.17 : CONFIGURATION CRON
# ----------------------------------------------------------------------------
configure_cron() {
    print_header
    print_section "EXERCICE 6.17 : CONFIGURATION CRON"
    
    local cron_file="/etc/cron.d/tp6-backup"
    
    echo "Planification proposée :"
    echo ""
    echo "Dimanche 02:00    : Backup complet"
    echo "Lundi-Samedi 02:00 : Backup incrémentale"
    echo "1er du mois 03:00 : Backup différentielle"
    echo "Tous les jours 04:00 : Nettoyage"
    echo "Vendredi 05:00    : Vérification"
    echo ""
    
    read -p "Créer cette planification ? (o/N) : " choice
    
    if [[ "$choice" != "o" && "$choice" != "O" ]]; then
        return
    fi
    
    # Créer le fichier cron
    cat > "$cron_file" << EOF
# TP6 - Planification des sauvegardes
# Généré le $(date)

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Backup complet - Dimanche 2h
0 2 * * 0 root /usr/local/bin/tp6.sh --cron full

# Backup incrémentale - Lundi à Samedi 2h
0 2 * * 1-6 root /usr/local/bin/tp6.sh --cron incremental

# Backup différentielle - 1er du mois 3h
0 3 1 * * root /usr/local/bin/tp6.sh --cron differential

# Nettoyage - Tous les jours 4h
0 4 * * * root /usr/local/bin/tp6.sh --cron cleanup

# Vérification - Vendredi 5h
0 5 * * 5 root /usr/local/bin/tp6.sh --cron verify
EOF
    
    chmod 644 "$cron_file"
    
    log "SUCCESS" "Fichier cron créé : $cron_file"
    echo ""
    echo "Contenu :"
    cat "$cron_file"
    
    echo ""
    read -p "Redémarrer cron ? (o/N) : " restart_choice
    if [[ "$restart_choice" == "o" || "$restart_choice" == "O" ]]; then
        /etc/init.d/cronie restart
        log "SUCCESS" "Service cron redémarré"
    fi
    
    read -p "Appuyez sur Entrée pour continuer..."
}

# ----------------------------------------------------------------------------
# FONCTION DE SAUVEGARDE PRINCIPALE
# ----------------------------------------------------------------------------
perform_backup() {
    local backup_type=$1
    
    print_header
    print_section "SAUVEGARDE : $backup_type"
    
    # Vérifier le point de montage
    if ! mountpoint -q "$BACKUP_ROOT" 2>/dev/null; then
        log "ERROR" "$BACKUP_ROOT n'est pas monté"
        echo "Utilisez l'option 'Configurer le disque' d'abord."
        read -p "Appuyez sur Entrée..."
        return 1
    fi
    
    # Créer la structure
    local backup_path="$BACKUP_ROOT/${DATE}_${backup_type}"
    mkdir -p "$backup_path"/{homes,mysql,ldap,wordpress,logs,system}
    
    log "INFO" "Début : $backup_type → $backup_path"
    
    # Informations système
    save_system_info "$backup_path"
    
    # Exécuter les sauvegardes
    local errors=0
    
    echo ""
    echo "Progression :"
    echo "────────────"
    
    echo -n "1. Homes... "
    if backup_homes "$backup_type" "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    echo -n "2. MySQL... "
    if backup_mysql "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    echo -n "3. LDAP... "
    if backup_ldap "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    echo -n "4. WordPress... "
    if backup_wordpress "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    echo -n "5. Checksums... "
    if generate_checksums "$backup_path"; then
        echo "✓"
    else
        echo "✗"
        errors=$((errors + 1))
    fi
    
    # Rapport
    create_backup_report "$backup_path" "$backup_type" "$errors"
    
    echo ""
    echo "RÉSUMÉ :"
    echo "────────"
    echo "Type     : $backup_type"
    echo "Date     : $(date)"
    echo "Chemin   : $backup_path"
    echo "Taille   : $(du -sh $backup_path | cut -f1)"
    echo "Erreurs  : $errors"
    echo ""
    
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "Sauvegarde réussie"
    else
        log "WARNING" "Sauvegarde avec $errors erreur(s)"
    fi
    
    read -p "Appuyez sur Entrée..."
    return $errors
}

save_system_info() {
    local backup_path=$1
    
    uname -a > "$backup_path/system/uname.txt"
    df -h > "$backup_path/system/disk_usage.txt"
    free -h > "$backup_path/system/memory.txt"
    ps aux > "$backup_path/system/processes.txt"
    getent passwd > "$backup_path/system/users.txt"
}

backup_wordpress() {
    local backup_path=$1
    
    if [ ! -d "$WORDPRESS_DIR" ]; then
        log "WARNING" "WordPress non trouvé : $WORDPRESS_DIR"
        return 1
    fi
    
    # Fichiers
    tar -czf "$backup_path/wordpress/files_${DATE}.tar.gz" \
        -C "$(dirname $WORDPRESS_DIR)" \
        "$(basename $WORDPRESS_DIR)"
    
    # Base de données
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

Date     : $(date)
Type     : $backup_type
Hôte     : $(hostname)
Chemin   : $backup_path

STATISTIQUES
────────────
Taille   : $(du -sh $backup_path | cut -f1)
Erreurs  : $errors

CONTENU
───────
$(find "$backup_path" -type f -name "*.gz" -o -name "*.tar" | xargs -I {} basename {} | sort)

VÉRIFICATION
────────────
$(if [ $errors -eq 0 ]; then echo "STATUS : ✓ SUCCÈS"; else echo "STATUS : ✗ ÉCHEC"; fi)

RESTAURATION
────────────
Pour restaurer :
1. $0 --restore $backup_path
2. Suivre les instructions
EOF
}

# ----------------------------------------------------------------------------
# EXERCICE 6.18 : GÉNÉRATION DE BACKUPS TEST
# ----------------------------------------------------------------------------
generate_test_backups() {
    print_header
    print_section "EXERCICE 6.18 : GÉNÉRATION DE BACKUPS TEST"
    
    echo "Cet exercice génère :"
    echo "1. Un backup complet"
    echo "2. Un backup incrémentale"
    echo ""
    echo "Ces backups serviront pour les exercices suivants."
    echo ""
    
    read -p "Générer un backup complet ? (o/N) : " choice
    if [[ "$choice" == "o" || "$choice" == "O" ]]; then
        perform_backup "full"
    fi
    
    echo ""
    read -p "Générer un backup incrémentale ? (o/N) : " choice
    if [[ "$choice" == "o" || "$choice" == "O" ]]; then
        # Créer un fichier de test
        touch /home/test_file_incr_$DATE.txt
        echo "Test pour backup incrémentale" > /home/test_file_incr_$DATE.txt
        
        perform_backup "incremental"
        
        # Nettoyer
        rm -f /home/test_file_incr_$DATE.txt
    fi
    
    # Lister
    echo ""
    echo "BACKUPS DISPONIBLES :"
    echo "────────────────────"
    list_backups
}

# ----------------------------------------------------------------------------
# EXERCICE 6.19 : RESTAURATION COMPLÈTE
# ----------------------------------------------------------------------------
restore_complete() {
    print_header
    print_section "EXERCICE 6.19 : RESTAURATION COMPLÈTE"
    
    echo "Cette fonction simule la restauration sur une nouvelle machine."
    echo ""
    
    # Lister les sauvegardes
    echo "Sauvegardes disponibles :"
    echo "───────────────────────"
    list_backups_simple
    
    echo ""
    read -p "Date de la sauvegarde (ex: 20240115_020000) : " backup_date
    
    if [ -z "$backup_date" ]; then
        log "ERROR" "Date non spécifiée"
        read -p "Appuyez sur Entrée..."
        return
    fi
    
    # Trouver la sauvegarde
    local backup_path=$(find "$BACKUP_ROOT" -type d -name "*${backup_date}*" | head -1)
    
    if [ -z "$backup_path" ] || [ ! -d "$backup_path" ]; then
        log "ERROR" "Sauvegarde non trouvée"
        read -p "Appuyez sur Entrée..."
        return
    fi
    
    echo ""
    echo "Sauvegarde : $backup_path"
    echo "Taille     : $(du -sh $backup_path | cut -f1)"
    echo ""
    
    # Menu de restauration
    echo "QUE RESTAURER ?"
    echo "───────────────"
    echo "1. Tout (restauration complète)"
    echo "2. Uniquement les homes"
    echo "3. Uniquement MySQL"
    echo "4. Uniquement LDAP"
    echo "5. Uniquement WordPress"
    echo "6. Annuler"
    echo ""
    
    read -p "Choix [1-6] : " choice
    
    case $choice in
        1) restore_all "$backup_path" ;;
        2) restore_homes_only "$backup_path" ;;
        3) restore_mysql_only "$backup_path" ;;
        4) restore_ldap_only "$backup_path" ;;
        5) restore_wordpress_only "$backup_path" ;;
        *) echo "Annulé" ;;
    esac
    
    read -p "Appuyez sur Entrée..."
}

restore_all() {
    local backup_path=$1
    
    log "INFO" "Restauration complète"
    
    # Vérifier les checksums
    if [ -f "$backup_path/checksums.sha256" ]; then
        echo "Vérification intégrité..."
        if ! sha256sum -c "$backup_path/checksums.sha256" > /dev/null 2>&1; then
            log "ERROR" "Sauvegarde corrompue"
            return 1
        fi
    fi
    
    # Restaurer dans l'ordre
    restore_homes_only "$backup_path"
    restore_mysql_only "$backup_path"
    restore_ldap_only "$backup_path"
    restore_wordpress_only "$backup_path"
    
    log "SUCCESS" "Restauration complète terminée"
}

restore_homes_only() {
    local backup_path=$1
    
    log "INFO" "Restauration homes"
    
    local home_backup=$(find "$backup_path/homes" -name "homes_full_*.tar.gz" | sort -r | head -1)
    
    if [ ! -f "$home_backup" ]; then
        log "ERROR" "Aucune sauvegarde homes"
        return 1
    fi
    
    echo "Restauration depuis : $(basename $home_backup)"
    read -p "Confirmer ? (o/N) : " confirm
    
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
        return
    fi
    
    tar -xzf "$home_backup" -C /
    log "SUCCESS" "Homes restaurés"
}

restore_mysql_only() {
    local backup_path=$1
    
    log "INFO" "Restauration MySQL"
    
    local mysql_backup=$(find "$backup_path/mysql" -name "all_databases_*.sql.gz" | head -1)
    
    if [ ! -f "$mysql_backup" ]; then
        log "ERROR" "Aucune sauvegarde MySQL"
        return 1
    fi
    
    echo "Restauration depuis : $(basename $mysql_backup)"
    read -p "Confirmer ? (o/N) : " confirm
    
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
        return
    fi
    
    gunzip -c "$mysql_backup" | mysql --user="$MYSQL_USER" --password="$MYSQL_PASS"
    log "SUCCESS" "MySQL restauré"
}

restore_ldap_only() {
    local backup_path=$1
    
    log "INFO" "Restauration LDAP"
    
    local ldap_backup=$(find "$backup_path/ldap" -name "ldap_*.ldif.gz" | head -1)
    
    if [ ! -f "$ldap_backup" ]; then
        log "ERROR" "Aucune sauvegarde LDAP"
        return 1
    fi
    
    echo "Restauration depuis : $(basename $ldap_backup)"
    read -p "Confirmer ? (o/N) : " confirm
    
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
        return
    fi
    
    /etc/init.d/slapd stop
    gunzip -c "$ldap_backup" | slapadd -v
    /etc/init.d/slapd start
    
    log "SUCCESS" "LDAP restauré"
}

restore_wordpress_only() {
    local backup_path=$1
    
    log "INFO" "Restauration WordPress"
    
    local wp_backup=$(find "$backup_path/wordpress" -name "files_*.tar.gz" | head -1)
    
    if [ ! -f "$wp_backup" ]; then
        log "ERROR" "Aucune sauvegarde WordPress"
        return 1
    fi
    
    echo "Restauration depuis : $(basename $wp_backup)"
    read -p "Confirmer ? (o/N) : " confirm
    
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
        return
    fi
    
    tar -xzf "$wp_backup" -C /
    log "SUCCESS" "WordPress restauré"
}

# ----------------------------------------------------------------------------
# EXERCICE 6.20 : RESTAURATION UTILISATEUR "raj"
# ----------------------------------------------------------------------------
restore_user_raj() {
    print_header
    print_section "EXERCICE 6.20 : RESTAURATION UTILISATEUR 'raj'"
    
    echo "Scénario : L'utilisateur 'raj' a supprimé son dossier 'htop-dev'"
    echo "et souhaite le récupérer depuis les sauvegardes."
    echo ""
    
    # Vérifier l'utilisateur
    if ! id "raj" > /dev/null 2>&1; then
        echo "L'utilisateur 'raj' n'existe pas."
        read -p "Le créer ? (o/N) : " choice
        
        if [[ "$choice" == "o" || "$choice" == "O" ]]; then
            useradd -m raj
            echo "Utilisateur 'raj' créé"
        else
            return
        fi
    fi
    
    # Chercher les sauvegardes récentes
    echo ""
    echo "Recherche des sauvegardes contenant 'raj'..."
    
    local recent_backups=$(find "$BACKUP_ROOT" -type d -name "*_full" | sort -r | head -3)
    
    for backup in $recent_backups; do
        local home_backup=$(find "$backup/homes" -name "*.tar.gz" | head -1)
        
        if [ -f "$home_backup" ] && tar -tzf "$home_backup" | grep -q "^home/raj/"; then
            echo ""
            echo "✓ Sauvegarde trouvée : $(basename $backup)"
            echo "  Date : $(echo $backup | grep -o '[0-9]\{8\}_[0-9]\{6\}')"
            
            read -p "Restaurer 'raj' depuis cette sauvegarde ? (o/N) : " choice
            
            if [[ "$choice" == "o" || "$choice" == "O" ]]; then
                restore_single_user "raj" "$home_backup"
                return
            fi
        fi
    done
    
    log "ERROR" "Aucune sauvegarde de 'raj' trouvée"
    read -p "Appuyez sur Entrée..."
}

restore_single_user() {
    local username=$1
    local backup_file=$2
    
    log "INFO" "Restauration de $username"
    
    # Sauvegarde des fichiers actuels
    local backup_dir="/home/${username}_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "/home/$username" ]; then
        echo "Sauvegarde actuelle vers : $backup_dir"
        cp -r "/home/$username" "$backup_dir"
    fi
    
    # Extraire
    echo "Extraction depuis sauvegarde..."
    mkdir -p "/home/$username"
    
    tar -xzf "$backup_file" \
        --directory="/" \
        --preserve-permissions \
        "home/$username"
    
    # Permissions
    chown -R "$username:$username" "/home/$username"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "RESTAURATION RÉUSSIE"
    echo "────────────────────"
    echo "Utilisateur : $username"
    echo "Source      : $(basename $backup_file)"
    echo "Destination : /home/$username"
    echo "Sauvegarde  : $backup_dir"
    echo "═══════════════════════════════════════════════════"
    
    # Vérifier htop-dev
    if [ -d "/home/$username/htop-dev" ]; then
        echo ""
        echo "✅ Dossier 'htop-dev' restauré"
        ls -la "/home/$username/htop-dev/"
    else
        echo ""
        echo "⚠ Dossier 'htop-dev' non trouvé"
    fi
}

# ----------------------------------------------------------------------------
# EXERCICE 6.21 : LVM SNAPSHOTS (BONUS)
# ----------------------------------------------------------------------------
lvm_snapshots() {
    print_header
    print_section "EXERCICE 6.21 : LVM SNAPSHOTS (BONUS)"
    
    echo "Cette fonction utilise LVM pour créer des snapshots cohérents"
    echo "pendant les sauvegardes."
    echo ""
    
    # Vérifier LVM
    if ! command -v lvcreate > /dev/null 2>&1; then
        log "ERROR" "LVM non installé"
        echo "Installer : emerge -av sys-fs/lvm2"
        read -p "Appuyez sur Entrée..."
        return
    fi
    
    # Chercher un volume LVM pour /home
    local home_lv=$(df /home 2>/dev/null | awk 'NR==2 {print $1}')
    
    if [[ ! $home_lv =~ /dev/mapper/ ]]; then
        log "ERROR" "/home n'est pas sur LVM"
        echo "Configuration LVM requise."
        read -p "Appuyez sur Entrée..."
        return
    fi
    
    # Informations
    local vg_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f1)
    local lv_name=$(echo "$home_lv" | cut -d'/' -f4 | cut -d'-' -f2)
    
    echo "LVM détecté :"
    echo "• Volume Group : $vg_name"
    echo "• Logical Volume : $lv_name"
    echo "• Chemin : $home_lv"
    echo ""
    
    echo "Options :"
    echo "1. Créer un snapshot"
    echo "2. Lister les snapshots"
    echo "3. Supprimer un snapshot"
    echo "4. Retour"
    echo ""
    
    read -p "Choix [1-4] : " choice
    
    case $choice in
        1)
            create_snapshot "$vg_name" "$lv_name"
            ;;
        2)
            list_snapshots "$vg_name"
            ;;
        3)
            delete_snapshot "$vg_name"
            ;;
    esac
    
    read -p "Appuyez sur Entrée..."
}

create_snapshot() {
    local vg=$1
    local lv=$2
    
    local snapshot_name="${lv}_snapshot_$(date +%Y%m%d_%H%M%S)"
    local snapshot_size="5G"
    
    echo "Création snapshot : $snapshot_name"
    echo "Taille : $snapshot_size"
    echo ""
    
    read -p "Confirmer ? (o/N) : " choice
    
    if [[ "$choice" != "o" && "$choice" != "O" ]]; then
        return
    fi
    
    if lvcreate --snapshot \
                --name "$snapshot_name" \
                --size "$snapshot_size" \
                "/dev/$vg/$lv"; then
        log "SUCCESS" "Snapshot créé"
        
        # Monter
        local mount_point="/mnt/snapshot_$snapshot_name"
        mkdir -p "$mount_point"
        
        if mount -o ro "/dev/$vg/$snapshot_name" "$mount_point"; then
            echo ""
            echo "Snapshot monté sur : $mount_point"
            echo "Contenu :"
            ls -la "$mount_point/"
            
            read -p "Démonter ? (o/N) : " unmount_choice
            if [[ "$unmount_choice" == "o" || "$unmount_choice" == "O" ]]; then
                umount "$mount_point"
                rmdir "$mount_point"
                log "INFO" "Snapshot démonté"
            fi
        fi
    else
        log "ERROR" "Échec création snapshot"
    fi
}

# ----------------------------------------------------------------------------
# FONCTIONS UTILITAIRES
# ----------------------------------------------------------------------------
list_backups() {
    echo "BACKUPS DISPONIBLES :"
    echo "────────────────────"
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "Aucune sauvegarde"
        return
    fi
    
    local backups=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | sort -r)
    
    if [ -z "$backups" ]; then
        echo "Aucune sauvegarde"
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

cleanup_old() {
    print_header
    print_section "NETTOYAGE DES ANCIENNES SAUVEGARDES"
    
    echo "Suppression des sauvegardes de plus de $RETENTION_DAYS jours..."
    echo ""
    
    local count=0
    local freed=0
    
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | while read backup; do
        local backup_date=$(basename "$backup" | cut -d_ -f1)
        local backup_epoch=$(date -d "${backup_date:0:4}-${backup_date:4:2}-${backup_date:6:2}" +%s 2>/dev/null)
        local current_epoch=$(date +%s)
        local age_days=$(( (current_epoch - backup_epoch) / 86400 ))
        
        if [ $age_days -gt $RETENTION_DAYS ]; then
            local size=$(du -sk "$backup" 2>/dev/null | cut -f1)
            echo "  Suppression : $(basename $backup) ($age_days jours, $(echo "scale=1; $size/1024" | bc) MB)"
            rm -rf "$backup"
            count=$((count + 1))
            freed=$((freed + size))
        fi
    done
    
    echo ""
    echo "RÉSUMÉ :"
    echo "• Sauvegardes supprimées : $count"
    echo "• Espace libéré : $(echo "scale=1; $freed/1024" | bc) MB"
    
    read -p "Appuyez sur Entrée..."
}

verify_system() {
    print_header
    print_section "VÉRIFICATION DU SYSTÈME"
    
    local errors=0
    
    echo "1. Point de montage..."
    if mountpoint -q "$BACKUP_ROOT"; then
        echo "   ✓ $BACKUP_ROOT monté"
        echo "     Espace : $(df -h $BACKUP_ROOT | awk 'NR==2 {print $4}') libre"
    else
        echo "   ✗ $BACKUP_ROOT non monté"
        errors=$((errors + 1))
    fi
    
    echo ""
    echo "2. Permissions..."
    local perms=$(stat -c "%a" "$BACKUP_ROOT" 2>/dev/null)
    if [ "$perms" = "750" ] || [ "$perms" = "700" ]; then
        echo "   ✓ Permissions $perms OK"
    else
        echo "   ⚠ Permissions $perms non optimales"
    fi
    
    echo ""
    echo "3. Dépendances..."
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
    echo "4. Services..."
    if /etc/init.d/mysql status > /dev/null 2>&1 || /etc/init.d/mariadb status > /dev/null 2>&1; then
        echo "   ✓ MySQL/MariaDB actif"
    else
        echo "   ⚠ MySQL/MariaDB inactif"
    fi
    
    if /etc/init.d/slapd status > /dev/null 2>&1; then
        echo "   ✓ LDAP actif"
    else
        echo "   ⚠ LDAP inactif"
    fi
    
    echo ""
    echo "5. Sauvegardes..."
    local backup_count=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" 2>/dev/null | wc -l)
    if [ $backup_count -gt 0 ]; then
        echo "   ✓ $backup_count sauvegarde(s)"
        
        local last_backup=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*_*" | sort -r | head -1)
        if [ -d "$last_backup" ]; then
            local checksum_file="$last_backup/checksums.sha256"
            if [ -f "$checksum_file" ]; then
                if sha256sum -c "$checksum_file" > /dev/null 2>&1; then
                    echo "   ✓ Dernière sauvegarde OK : $(basename $last_backup)"
                else
                    echo "   ✗ Dernière sauvegarde corrompue"
                    errors=$((errors + 1))
                fi
            fi
        fi
    else
        echo "   ⚠ Aucune sauvegarde"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    if [ $errors -eq 0 ]; then
        echo "✅ SYSTÈME OK"
    else
        echo "⚠ $errors ERREUR(S)"
    fi
    echo "═══════════════════════════════════════════════════"
    
    read -p "Appuyez sur Entrée..."
}

show_logs() {
    print_header
    print_section "CONSULTATION DES LOGS"
    
    echo "Logs disponibles :"
    echo "────────────────"
    ls -la "$LOG_DIR/"*.log 2>/dev/null || echo "Aucun log"
    echo ""
    
    read -p "Nom du fichier (sans chemin) : " logfile
    if [ -f "$LOG_DIR/$logfile" ]; then
        echo ""
        echo "Contenu de $logfile :"
        echo "────────────────────"
        tail -50 "$LOG_DIR/$logfile"
    else
        log "ERROR" "Fichier non trouvé"
    fi
    
    read -p "Appuyez sur Entrée..."
}

# ----------------------------------------------------------------------------
# MENU PRINCIPAL
# ----------------------------------------------------------------------------
show_menu() {
    while true; do
        print_header
        echo "MENU PRINCIPAL"
        echo "══════════════════════════════════════════════════════════════"
        echo ""
        
        echo "📚 THÉORIE ET CONFIGURATION :"
        echo "  1. Exercices 6.1-6.5 - Théorie et planning"
        echo "  2. Exercices 6.6-6.7 - Configurer le disque de backup"
        echo "  3. Installation des dépendances (résout problème MariaDB)"
        echo "  4. Exercice 6.9 - Organisation des backups"
        echo "  5. Exercice 6.17 - Configurer cron"
        echo ""
        
        echo "💾 SAUVEGARDES :"
        echo "  6. Exercice 6.18 - Générer backups test (full + incr)"
        echo "  7. Sauvegarde complète (full)"
        echo "  8. Sauvegarde incrémentale (incremental)"
        echo "  9. Sauvegarde différentielle (differential)"
        echo ""
        
        echo "🔄 RESTAURATION :"
        echo "  10. Exercice 6.19 - Restauration complète"
        echo "  11. Exercice 6.20 - Restaurer utilisateur 'raj'"
        echo ""
        
        echo "⚙️  ADMINISTRATION :"
        echo "  12. Exercice 6.21 - LVM Snapshots (bonus)"
        echo "  13. Lister les sauvegardes"
        echo "  14. Nettoyer anciennes sauvegardes"
        echo "  15. Vérifier l'état du système"
        echo "  16. Consulter les logs"
        echo ""
        
        echo "  0. Quitter"
        echo ""
        
        read -p "Votre choix [0-16] : " choice
        
        case $choice in
            1) show_theory ;;
            2) configure_disk ;;
            3) install_dependencies ;;
            4) show_organization ;;
            5) configure_cron ;;
            6) generate_test_backups ;;
            7) perform_backup "full" ;;
            8) perform_backup "incremental" ;;
            9) perform_backup "differential" ;;
            10) restore_complete ;;
            11) restore_user_raj ;;
            12) lvm_snapshots ;;
            13) 
                print_header
                list_backups
                read -p "Appuyez sur Entrée..."
                ;;
            14) cleanup_old ;;
            15) verify_system ;;
            16) show_logs ;;
            0)
                echo ""
                echo "Merci d'avoir utilisé le script TP6 !"
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
# MODE CRON (non-interactif)
# ----------------------------------------------------------------------------
cron_mode() {
    local action=$1
    
    case $action in
        "full") perform_backup "full" ;;
        "incremental") perform_backup "incremental" ;;
        "differential") perform_backup "differential" ;;
        "cleanup") cleanup_old ;;
        "verify") verify_system ;;
        *) echo "Action cron inconnue: $action" ;;
    esac
}

# ----------------------------------------------------------------------------
# POINT D'ENTRÉE
# ----------------------------------------------------------------------------
main() {
    # Créer répertoire logs
    mkdir -p "$LOG_DIR"
    
    # Vérifier root
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en tant que root."
        echo "Utilisez: sudo $0"
        exit 1
    fi
    
    # Mode d'exécution
    case "$1" in
        "--cron")
            cron_mode "$2"
            ;;
        "--restore")
            if [ -d "$2" ]; then
                restore_all "$2"
            else
                echo "Chemin invalide: $2"
                exit 1
            fi
            ;;
        "--help"|"-h")
            print_header
            echo "UTILISATION:"
            echo "  $0                    # Mode interactif avec menu"
            echo "  $0 --cron <action>   # Mode cron"
            echo "  $0 --restore <path>  # Restauration rapide"
            echo "  $0 --help            # Aide"
            echo ""
            echo "ACTIONS CRON:"
            echo "  full, incremental, differential, cleanup, verify"
            echo ""
            exit 0
            ;;
        *)
            show_menu
            ;;
    esac
}

# ----------------------------------------------------------------------------
# LANCER LE SCRIPT
# ----------------------------------------------------------------------------
main "$@"