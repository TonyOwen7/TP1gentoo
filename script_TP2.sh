#!/bin/bash

# Script complet pour le TP LVM sur Gentoo
# A exécuter en tant que root
# ATTENTION: Ce script modifie le partitionnement et peut être destructeur

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonctions de logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérification que le script est exécuté en root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

# Installation et configuration de LVM
install_lvm() {
    log_info "Installation de LVM2..."
    
    # Configuration des USE flags
    if [[ ! -f /etc/portage/package.use/lvm ]]; then
        mkdir -p /etc/portage/package.use
        echo "sys-fs/lvm2 lvm" >> /etc/portage/package.use/lvm
        log_info "USE flags configurés"
    fi
    
    # Installation de LVM
    emerge --ask --verbose sys-fs/lvm2
    
    # Activation des services
    rc-update add lvm boot
    rc-update add lvmetad boot
    /etc/init.d/lvm start
    /etc/init.d/lvmetad start
    
    log_info "LVM installé et configuré"
}

# Exercice 2.13 - Migration de /home vers LVM
migrate_home_to_lvm() {
    log_info "Début de la migration de /home vers LVM"
    
    # Sauvegarde des processus en cours sur /home
    log_info "Vérification des processus utilisant /home..."
    if lsof +D /home &>/dev/null; then
        log_warn "Des processus utilisent /home, arrêt en cours..."
        rc-service sshd stop 2>/dev/null || true
        pkill -9 -u $(id -u username) 2>/dev/null || true
        sleep 2
    fi
    
    # Sauvegarde de /home
    log_info "Sauvegarde de /home..."
    local backup_file="/root/home_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_file" -C /home . --exclude="*backup*" --exclude=".cache"
    
    if [[ $? -ne 0 ]]; then
        log_error "Échec de la sauvegarde de /home"
        exit 1
    fi
    
    log_info "Sauvegarde terminée: $backup_file"
    
    # Identification de la partition /home actuelle
    local home_partition=$(mount | grep " /home " | awk '{print $1}')
    if [[ -z "$home_partition" ]]; then
        log_error "Impossible de trouver la partition /home"
        exit 1
    fi
    
    log_info "Partition /home actuelle: $home_partition"
    
    # Demande de confirmation
    read -p "Voulez-vous vraiment continuer? Cette opération va supprimer la partition $home_partition [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Opération annulée"
        exit 0
    fi
    
    # Démontage de /home
    log_info "Démontage de /home..."
    umount /home
    
    # Suppression et recréation de la partition
    local device=$(echo "$home_partition" | sed 's/[0-9]*$//')
    local partition_num=$(echo "$home_partition" | grep -o '[0-9]*$')
    
    log_info "Modification de la partition $partition_num sur $device"
    
    # Utilisation de sfdisk pour modifier la partition
    sfdisk --delete "$device" "$partition_num"
    echo "$(sfdisk -d "$device" | grep -v "$home_partition")" | sfdisk "$device"
    
    # Recréation de la partition avec le même début mais type LVM
    local start_sector=$(sfdisk -d "$device" | grep "$home_partition" | grep -o 'start=[0-9]*' | cut -d= -f2)
    
    if [[ -n "$start_sector" ]]; then
        echo "$start_sector,+,-,8e" | sfdisk -a "$device"
    else
        # Si on ne peut pas déterminer le secteur de début, on utilise fdisk
        log_info "Utilisation de fdisk pour la création de la partition LVM..."
        fdisk "$device" << EOF
n
p
$partition_num


t
$partition_num
8e
w
EOF
    fi
    
    # Rechargement de la table de partitions
    partprobe "$device"
    sleep 2
    
    # Configuration LVM
    local new_partition="${device}${partition_num}"
    log_info "Création du volume physique sur $new_partition"
    pvcreate "$new_partition"
    
    log_info "Création du volume group vg_home"
    vgcreate vg_home "$new_partition"
    
    log_info "Création du volume logique home"
    lvcreate -n home -l 100%FREE vg_home
    
    # Formatage
    log_info "Formatage du volume logique en ext4"
    mkfs.ext4 /dev/vg_home/home
    
    # Montage et restauration
    log_info "Montage du nouveau volume /home"
    mount /dev/vg_home/home /home
    
    log_info "Restauration des données..."
    tar -xzf "$backup_file" -C /home
    
    # Configuration du fstab
    log_info "Configuration de /etc/fstab"
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Suppression de l'ancienne entrée /home
    sed -i '\|/home|d' /etc/fstab
    
    # Ajout de la nouvelle entrée
    echo "/dev/vg_home/home   /home   ext4    defaults    0 2" >> /etc/fstab
    
    # Vérification
    log_info "Vérification du montage..."
    mount -a
    df -h /home
    
    log_info "Migration de /home vers LVM terminée avec succès"
}

# Exercice 2.14 - Extension avec nouveau disque
extend_with_new_disk() {
    log_info "Configuration d'un nouveau disque pour extension LVM"
    
    # Détection des disques disponibles
    log_info "Disques disponibles:"
    lsblk
    
    read -p "Entrez le chemin du nouveau disque (ex: /dev/sdb): " new_disk
    
    if [[ ! -b "$new_disk" ]]; then
        log_error "Disque $new_disk non trouvé"
        exit 1
    fi
    
    # Partitionnement du nouveau disque
    log_info "Partitionnement de $new_disk..."
    parted -s "$new_disk" mklabel msdos
    parted -s "$new_disk" mkpart primary 0% 100%
    parted -s "$new_disk" set 1 lvm on
    
    local new_partition="${new_disk}1"
    sleep 2
    
    # Extension du LVM
    log_info "Création du volume physique sur $new_partition"
    pvcreate "$new_partition"
    
    log_info "Extension du volume group vg_home"
    vgextend vg_home "$new_partition"
    
    log_info "Extension du volume logique home"
    lvextend -l +100%FREE /dev/vg_home/home
    
    log_info "Extension du système de fichiers"
    resize2fs /dev/vg_home/home
    
    # Vérification
    log_info "Vérification de l'extension..."
    df -h /home
    vgs
    lvs
    
    log_info "Extension avec nouveau disque terminée"
}

# Exercice 2.15 - Monitoring et sauvegarde
setup_monitoring() {
    log_info "Configuration du monitoring pour environnement physique"
    
    # Installation des outils de monitoring
    emerge --ask sys-block/smartmontools
    
    # Configuration SMART
    local disks=$(lsblk -d -o NAME | grep -v NAME | grep -v loop)
    for disk in $disks; do
        local disk_path="/dev/$disk"
        if [[ -b "$disk_path" ]]; then
            log_info "Configuration SMART pour $disk_path"
            smartctl --smart=on --offlineauto=on --saveauto=on "$disk_path"
        fi
    done
    
    # Script de sauvegarde des métadonnées LVM
    cat > /usr/local/bin/lvm_backup.sh << 'EOF'
#!/bin/bash
# Sauvegarde automatique des métadonnées LVM
BACKUP_DIR="/root/lvm_backup"
mkdir -p "$BACKUP_DIR"
vgcfgbackup -f "$BACKUP_DIR/vg_backup_$(date +%Y%m%d_%H%M%S)"
# Rotation: garder 7 jours
find "$BACKUP_DIR" -name "vg_backup_*" -mtime +7 -delete
EOF
    
    chmod +x /usr/local/bin/lvm_backup.sh
    
    # Crontab pour sauvegarde quotidienne
    echo "0 2 * * * root /usr/local/bin/lvm_backup.sh" >> /etc/crontab
    
    # Script de monitoring santé des disques
    cat > /usr/local/bin/disk_health_check.sh << 'EOF'
#!/bin/bash
# Vérification santé des disques
for disk in $(lsblk -d -o NAME | grep -v NAME | grep -v loop); do
    disk_path="/dev/$disk"
    if smartctl -H "$disk_path" | grep -q "FAILED"; then
        echo "ALERTE: Disque $disk_path en état de défaillance" | mail -s "Alerte disque" root
    fi
done
EOF
    
    chmod +x /usr/local/bin/disk_health_check.sh
    
    log_info "Monitoring configuré"
    log_warn "N'oubliez pas de configurer RAID pour les environnements de production!"
}

# Fonction d'affichage des informations système
show_system_info() {
    log_info "Informations système actuelles:"
    echo "=== Partitions ==="
    lsblk
    echo "=== LVM ==="
    pvs 2>/dev/null || echo "Aucun volume physique LVM"
    vgs 2>/dev/null || echo "Aucun volume group LVM"
    lvs 2>/dev/null || echo "Aucun volume logique LVM"
    echo "=== Montages ==="
    df -h | grep -E "(home|/dev/mapper)"
}

# Menu principal
main_menu() {
    clear
    echo "========================================="
    echo "  TP LVM Complet - Gentoo"
    echo "========================================="
    echo
    echo "1. Installation de LVM"
    echo "2. Migration de /home vers LVM (Exercice 2.13)"
    echo "3. Extension avec nouveau disque (Exercice 2.14)"
    echo "4. Configuration monitoring (Exercice 2.15)"
    echo "5. Informations système"
    echo "6. Tout exécuter (séquentiellement)"
    echo "0. Quitter"
    echo
    read -p "Choisissez une option [0-6]: " choice
    
    case $choice in
        1) install_lvm ;;
        2) migrate_home_to_lvm ;;
        3) extend_with_new_disk ;;
        4) setup_monitoring ;;
        5) show_system_info ;;
        6)
            install_lvm
            migrate_home_to_lvm
            extend_with_new_disk
            setup_monitoring
            ;;
        0) exit 0 ;;
        *) log_error "Option invalide" ;;
    esac
    
    read -p "Appuyez sur Entrée pour continuer..."
    main_menu
}

# Point d'entrée principal
main() {
    check_root
    log_info "Début du script TP LVM Gentoo"
    
    # Vérification de l'environnement
    if [[ ! -f /etc/gentoo-release ]]; then
        log_warn "Ce script est conçu pour Gentoo Linux"
        read -p "Continuer malgré tout? [y/N]: " continue_anyway
        if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    main_menu
}

# Capture CTRL+C
trap 'log_error "Script interrompu"; exit 1' INT

# Lancement du script
main "$@"