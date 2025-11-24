#!/usr/bin/env bash
# safe_grub_install_fixed.sh
# Installe GRUB sur Gentoo avec détection automatique des partitions
# Usage: run as root
# chmod +x safe_grub_install_fixed.sh
# ./safe_grub_install_fixed.sh

set -euo pipefail

# === Fonctions couleurs ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Détection automatique des partitions ===
detect_partitions() {
    info "Détection automatique des partitions..."
    
    # Lister tous les disques disponibles
    DISKS=$(lsblk -ndo NAME | grep -E '^[a-z]+$')
    if [ -z "$DISKS" ]; then
        err "Aucun disque détecté"
    fi
    
    # Prendre le premier disque (sda, vda, etc.)
    MAIN_DISK="/dev/$(echo "$DISKS" | head -1)"
    info "Disque principal détecté: $MAIN_DISK"
    
    # Détecter les partitions
    PARTITIONS=$(lsblk -nlo NAME "$MAIN_DISK" | tail -n +2)
    
    # Variables pour stocker les partitions détectées
    BOOT_PART=""
    ROOT_PART=""
    SWAP_PART=""
    HOME_PART=""
    
    for part in $PARTITIONS; do
        FULL_PATH="/dev/$part"
        FSTYPE=$(lsblk -no FSTYPE "$FULL_PATH" 2>/dev/null || echo "")
        MOUNTPOINT=$(lsblk -no MOUNTPOINT "$FULL_PATH" 2>/dev/null || echo "")
        SIZE=$(lsblk -no SIZE "$FULL_PATH" 2>/dev/null || echo "")
        
        info "Partition $FULL_PATH: Type=$FSTYPE, Mount=$MOUNTPOINT, Size=$SIZE"
        
        # Détection basée sur le type de système de fichiers et la taille
        case "$FSTYPE" in
            "ext2"|"ext3"|"ext4"|"vfat"|"fat32")
                if [ "$SIZE" = "256M" ] || [ "$SIZE" = "512M" ] || [ "$SIZE" = "1G" ]; then
                    BOOT_PART="$FULL_PATH"
                    ok "Partition boot détectée: $BOOT_PART"
                elif [ -z "$ROOT_PART" ] && [ "$SIZE" = "10G" ] || [ "$SIZE" = "15G" ] || [ "$SIZE" = "20G" ]; then
                    ROOT_PART="$FULL_PATH"
                    ok "Partition root détectée: $ROOT_PART"
                elif [ -z "$HOME_PART" ] && [ "$SIZE" = "5G" ] || [ "$SIZE" = "10G" ] || echo "$SIZE" | grep -q "G"; then
                    HOME_PART="$FULL_PATH"
                    ok "Partition home détectée: $HOME_PART"
                fi
                ;;
            "swap")
                SWAP_PART="$FULL_PATH"
                ok "Partition swap détectée: $SWAP_PART"
                ;;
            *)
                # Si pas de FSTYPE mais mountpoint /boot ou /
                if [ "$MOUNTPOINT" = "/boot" ]; then
                    BOOT_PART="$FULL_PATH"
                    ok "Partition boot (par mountpoint): $BOOT_PART"
                elif [ "$MOUNTPOINT" = "/" ]; then
                    ROOT_PART="$FULL_PATH"
                    ok "Partition root (par mountpoint): $ROOT_PART"
                fi
                ;;
        esac
    done
    
    # Fallback: utiliser l'ordre des partitions si la détection échoue
    if [ -z "$BOOT_PART" ]; then
        BOOT_CANDIDATES=$(echo "$PARTITIONS" | head -1)
        if [ -n "$BOOT_CANDIDATES" ]; then
            BOOT_PART="/dev/$(echo "$BOOT_CANDIDATES" | head -1)"
            warn "Utilisation partition boot par défaut: $BOOT_PART"
        fi
    fi
    
    if [ -z "$ROOT_PART" ]; then
        ROOT_CANDIDATES=$(echo "$PARTITIONS" | sed -n '2p')
        if [ -n "$ROOT_CANDIDATES" ]; then
            ROOT_PART="/dev/$(echo "$ROOT_CANDIDATES" | head -1)"
            warn "Utilisation partition root par défaut: $ROOT_PART"
        else
            ROOT_PART="/dev/$(echo "$PARTITIONS" | head -1)"
            warn "Utilisation première partition comme root: $ROOT_PART"
        fi
    fi
    
    # Validation finale
    [ -n "$ROOT_PART" ] || err "Impossible de détecter la partition root"
    [ -b "$ROOT_PART" ] || err "Partition root $ROOT_PART non trouvée"
    
    info "=== Partitions détectées ==="
    info "Disque: $MAIN_DISK"
    info "Boot: $BOOT_PART"
    info "Root: $ROOT_PART"
    info "Swap: $SWAP_PART"
    info "Home: $HOME_PART"
    
    # Export des variables
    export DISK="$MAIN_DISK"
    export PART_BOOT="$BOOT_PART"
    export PART_ROOT="$ROOT_PART"
    export PART_SWAP="$SWAP_PART"
    export PART_HOME="$HOME_PART"
}

# === Configuration avec valeurs par défaut ===
MNT="/mnt/gentoo"
BOOT_DIR="/boot"
EFI_DIR="/boot/efi"
GRUB_ID="Gentoo"

# === Root check ===
[ "$(id -u)" -eq 0 ] || err "Run as root!"

# === Détection automatique ===
detect_partitions

# === Vérification partitions ===
info "Vérification des partitions..."
[ -b "$PART_ROOT" ] || err "Partition root $PART_ROOT non trouvée"

if [ -n "$PART_BOOT" ]; then
    [ -b "$PART_BOOT" ] || warn "Partition boot $PART_BOOT non trouvée, utilisation de root pour boot"
else
    warn "Aucune partition boot détectée, utilisation de la partition root pour boot"
    PART_BOOT="$PART_ROOT"
fi

# === Montage safe ===
info "Montage des partitions..."

# Nettoyage préalable
umount -R "$MNT" 2>/dev/null || true
mkdir -p "$MNT"

# Monter la partition root
mountpoint -q "$MNT" || mount "$PART_ROOT" "$MNT" || err "Échec montage root $PART_ROOT sur $MNT"
ok "Root $PART_ROOT monté sur $MNT"

# Monter boot si différent de root
if [ "$PART_BOOT" != "$PART_ROOT" ] && [ -n "$PART_BOOT" ]; then
    mkdir -p "$MNT$BOOT_DIR"
    if mountpoint -q "$MNT$BOOT_DIR"; then
        ok "Boot déjà monté"
    else
        mount "$PART_BOOT" "$MNT$BOOT_DIR" || warn "Échec montage boot $PART_BOOT, continuation sans partition boot séparée"
        ok "Boot $PART_BOOT monté sur $MNT$BOOT_DIR"
    fi
else
    warn "Utilisation de la partition root pour boot (pas de partition boot séparée)"
fi

# Monter home si détecté
if [ -n "$PART_HOME" ] && [ -b "$PART_HOME" ]; then
    mkdir -p "$MNT/home"
    mountpoint -q "$MNT/home" || mount "$PART_HOME" "$MNT/home" 2>/dev/null && ok "Home $PART_HOME monté" || warn "Échec montage home"
fi

# Activer swap si détecté
if [ -n "$PART_SWAP" ] && [ -b "$PART_SWAP" ]; then
    swapon "$PART_SWAP" 2>/dev/null && ok "Swap $PART_SWAP activé" || warn "Échec activation swap"
fi

# === Bind mounts ===
info "Montage des systèmes de fichiers virtuels..."
for fs in dev sys proc run; do
    mkdir -p "$MNT/$fs"
    if mountpoint -q "$MNT/$fs"; then
        ok "/$fs déjà monté"
    else
        mount --rbind "/$fs" "$MNT/$fs" && mount --make-rslave "$MNT/$fs" && ok "/$fs monté" || warn "Échec montage /$fs"
    fi
done

# Copy resolv.conf
if [ -f /etc/resolv.conf ]; then
    mkdir -p "$MNT/etc"
    cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" && ok "resolv.conf copié" || warn "Échec copie resolv.conf"
else
    warn "Fichier /etc/resolv.conf non trouvé"
fi

# === Vérification de l'environnement chroot ===
info "Vérification de l'environnement chroot..."
[ -f "$MNT/etc/os-release" ] && ok "Système Gentoo détecté" || warn "Système Gentoo non détecté dans $MNT"

# === Chroot installation ===
info "Entrée dans l'environnement chroot..."

chroot "$MNT" /bin/bash -eux <<CHROOT_EOF
set -euo pipefail

# Fonctions couleurs pour chroot
BLUE='\\033[1;34m'; GREEN='\\033[1;32m'; YELLOW='\\033[1;33m'; RED='\\033[1;31m'; NC='\\033[0m'
info() { printf "\${BLUE}[CHROOT INFO]\${NC} %s\\n" "\\\$*"; }
ok()   { printf "\${GREEN}[CHROOT OK]\${NC} %s\\n" "\\\$*"; }
warn() { printf "\${YELLOW}[CHROOT WARN]\${NC} %s\\n" "\\\$*"; }
err()  { printf "\${RED}[CHROOT ERROR]\${NC} %s\\n" "\\\$*"; exit 1; }

# PS1 pour bash
export PS1="(chroot) \\$ "

info "Début de l'installation GRUB dans chroot"

# Vérifier si GRUB est déjà installé
if command -v grub-install >/dev/null 2>&1; then
    GRUB_VERSION=\$(grub-install --version | head -1)
    ok "GRUB déjà installé: \$GRUB_VERSION"
else
    info "Installation de GRUB..."
    if emerge --noreplace --quiet sys-boot/grub 2>/dev/null; then
        ok "GRUB installé avec succès"
    else
        warn "Échec émergence silencieuse, tentative avec affichage"
        emerge --noreplace sys-boot/grub || err "Impossible d'installer GRUB"
    fi
fi

# Détecter BIOS ou UEFI
INSTALL_MODE="bios"
if [ -d "/sys/firmware/efi" ]; then
    INSTALL_MODE="uefi"
    ok "Mode UEFI détecté"
else
    ok "Mode BIOS détecté"
fi

# Vérifier la présence du répertoire /boot
if [ ! -d "/boot" ]; then
    warn "Création du répertoire /boot"
    mkdir -p /boot
fi

# Installer GRUB selon le mode
info "Installation GRUB en mode: \$INSTALL_MODE"

if [ "\$INSTALL_MODE" = "uefi" ]; then
    # Vérifier et monter l'EFI system partition
    if mountpoint -q /boot/efi; then
        ok "EFI partition déjà montée"
    else
        # Chercher la partition EFI
        EFI_PART=\$(lsblk -no NAME,FSTYPE,MOUNTPOINT | grep -i vfat | grep -v '/boot' | head -1 | cut -d' ' -f1)
        if [ -n "\$EFI_PART" ]; then
            mkdir -p /boot/efi
            mount "/dev/\$EFI_PART" /boot/efi && ok "EFI partition /dev/\$EFI_PART montée" || warn "Échec montage EFI partition"
        else
            warn "Aucune partition EFI détectée, utilisation de /boot"
        fi
    fi
    
    info "Installation UEFI GRUB..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=$GRUB_ID || \\
    grub-install --target=x86_64-efi --bootloader-id=$GRUB_ID || \\
    warn "Installation UEFI échouée, tentative BIOS"
    INSTALL_MODE="bios"  # Fallback to BIOS si UEFI échoue
fi

if [ "\$INSTALL_MODE" = "bios" ]; then
    info "Installation BIOS GRUB sur $DISK..."
    if grub-install --target=i386-pc $DISK; then
        ok "GRUB installé avec succès dans le MBR"
    else
        err "Échec installation BIOS GRUB"
    fi
fi

# Générer grub.cfg
info "Génération de grub.cfg..."
if [ -f /boot/grub/grub.cfg ]; then
    cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.bak && ok "Sauvegarde de l'ancien grub.cfg"
fi

if grub-mkconfig -o /boot/grub/grub.cfg; then
    ok "grub.cfg généré avec succès"
    info "Vérification du grub.cfg..."
    if [ -f /boot/grub/grub.cfg ] && [ -s /boot/grub/grub.cfg ]; then
        ok "grub.cfg valide (\$(stat -c%s /boot/grub/grub.cfg) octets)"
        # Afficher les entrées de boot
        echo "=== Entrées de boot détectées ==="
        grep "menuentry" /boot/grub/grub.cfg | head -5
    else
        warn "grub.cfg vide ou absent"
    fi
else
    warn "Échec génération grub.cfg, création manuelle..."
    mkdir -p /boot/grub
    cat > /boot/grub/grub.cfg << 'GRUB_CFG'
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro single
}
GRUB_CFG
    ok "grub.cfg manuel créé"
fi

# Vérification finale
info "Vérification finale de l'installation GRUB..."
if [ -f /boot/grub/grub.cfg ] && command -v grub-install >/dev/null 2>&1; then
    ok "✅ Installation GRUB terminée avec succès"
    info "📊 Résumé:"
    info "   Mode: \$INSTALL_MODE"
    info "   Disque: $DISK"
    info "   Boot: $PART_BOOT"
    info "   Root: $PART_ROOT"
else
    warn "⚠️  Problèmes détectés dans l'installation GRUB"
fi

CHROOT_EOF

# === Vérification finale hors chroot ===
ok "Retour du chroot"
info "Vérification finale..."

# Vérifier grub.cfg
if [ -f "$MNT/boot/grub/grub.cfg" ]; then
    ok "grub.cfg présent: $MNT/boot/grub/grub.cfg"
    echo "=== Extrait du grub.cfg ==="
    grep "menuentry" "$MNT/boot/grub/grub.cfg" | head -3
else
    warn "grub.cfg absent"
fi

# Vérifier MBR
info "Vérification du MBR..."
if dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    ok "GRUB détecté dans le MBR"
else
    warn "GRUB non détecté dans le MBR"
fi

# === Instructions finales ===
echo ""
ok "Script terminé avec succès!"
info "📋 Instructions pour redémarrer:"
cat <<EOF
1. Démonter les partitions:
   umount -R $MNT
   swapoff -a

2. Redémarrer:
   reboot

3. Si le système ne boot pas, essayer:
   - Appuyer sur 'c' dans GRUB pour le mode commande
   - Commandes manuelles:
     set root=(hd0,msdos1)
     linux /vmlinuz root=$PART_ROOT ro
     boot
EOF

warn "⚠️  NE PAS OUBLIER de démonter avant de redémarrer!"