#!/usr/bin/env bash
# safe_grub_install_fixed.sh
# Installation corrigée de GRUB pour Gentoo avec vérifications de montage
set -euo pipefail

# === Configuration ===
DISK="/dev/sda"
PART_BOOT="/dev/sda1"
PART_ROOT="/dev/sda3"
MNT="/mnt/gentoo"

# === Fonctions couleurs ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Fonction de montage sécurisé ===
safe_mount() {
    local device="$1"
    local mountpoint="$2"
    
    if mountpoint -q "$mountpoint"; then
        info "$mountpoint est déjà monté"
        return 0
    fi
    
    if [ ! -b "$device" ]; then
        err "Device $device non trouvé"
    fi
    
    mkdir -p "$mountpoint"
    if mount "$device" "$mountpoint"; then
        ok "Monté $device sur $mountpoint"
    else
        err "Échec du montage de $device sur $mountpoint"
    fi
}

# === Vérification root ===
[ "$(id -u)" -eq 0 ] || err "Exécutez en tant que root!"

# === Montage des partitions ===
info "Montage des partitions..."
safe_mount "$PART_ROOT" "$MNT"
safe_mount "$PART_BOOT" "$MNT/boot"

# === Bind mounts avec vérification ===
info "Configuration des bind mounts..."
for fs in dev sys proc; do
    if ! mountpoint -q "$MNT/$fs"; then
        mount --rbind "/$fs" "$MNT/$fs"
        mount --make-rslave "$MNT/$fs"
        ok "Bind mount $fs créé"
    else
        info "Bind mount $fs déjà présent"
    fi
done

if ! mountpoint -q "$MNT/run"; then
    mount --bind /run "$MNT/run"
    ok "Bind mount run créé"
fi

# === Installation GRUB dans chroot ===
info "Installation de GRUB dans le chroot..."
chroot "$MNT" /bin/bash <<'CHROOT_EOF'
set -e

echo "=== Vérification du système ==="
# Vérifier si nous sommes en UEFI ou BIOS
if [ -d /sys/firmware/efi ]; then
    echo "Système UEFI détecté"
    # Pour UEFI, s'assurer que la partition EFI est montée
    mkdir -p /boot/efi
    if ! mountpoint -q /boot/efi; then
        mount /dev/sda1 /boot/efi || echo "Attention: impossible de monter /boot/efi"
    fi
    
    # Installer GRUB pour UEFI
    command -v grub-install >/dev/null 2>&1 || {
        echo "Installation de GRUB..."
        emerge --noreplace sys-boot/grub || emerge sys-boot/grub
    }
    echo "Installation de GRUB pour UEFI..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
else
    echo "Système BIOS détecté"
    # Installer GRUB pour BIOS
    command -v grub-install >/dev/null 2>&1 || {
        echo "Installation de GRUB..."
        emerge --noreplace sys-boot/grub || emerge sys-boot/grub
    }
    echo "Installation de GRUB pour BIOS..."
    grub-install --target=i386-pc /dev/sda
fi

# Générer la configuration GRUB
echo "Génération de la configuration GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

# Vérifier l'installation
echo "=== Vérification de l'installation GRUB ==="
if [ -f /boot/grub/grub.cfg ]; then
    echo "✓ Configuration GRUB générée avec succès"
    echo "✓ Contenu de /boot :"
    ls -la /boot/
else
    echo "✗ Erreur: grub.cfg non généré"
    exit 1
fi
CHROOT_EOF

ok "Retour du chroot"
echo ""
echo "=== RÉSUMÉ ==="
echo "1. Partitions montées: ✓"
echo "2. GRUB installé: ✓" 
echo "3. Configuration générée: ✓"
echo ""
echo "Pour redémarrer:"
echo "umount -R $MNT"
echo "reboot"