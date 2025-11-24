#!/usr/bin/env bash
# safe_grub_install_fixed.sh
# Installation GRUB pour configuration: sda1=boot, sda2=swap, sda3=root
# Usage: run as root

set -euo pipefail

# === Configuration basée sur votre schéma ===
DISK="/dev/sda"
PART_BOOT="/dev/sda1"       # partition boot
PART_ROOT="/dev/sda3"       # partition root  
PART_SWAP="/dev/sda2"       # partition swap
MNT="/mnt/gentoo"
BOOT_DIR="/boot"
GRUB_ID="Gentoo"

# === Fonctions couleurs ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Vérification root ===
[ "$(id -u)" -eq 0 ] || err "Run as root!"

# === Vérification explicite des partitions ===
info "Vérification des partitions..."

check_partition() {
    local part="$1"
    local description="$2"
    
    if [ -b "$part" ]; then
        local fstype=$(lsblk -no FSTYPE "$part" 2>/dev/null || echo "unknown")
        local size=$(lsblk -no SIZE "$part" 2>/dev/null || echo "unknown")
        ok "$description: $part (Type: $fstype, Taille: $size)"
        return 0
    else
        err "$description: $part - PARTITION NON TROUVÉE!"
    fi
}

# Vérifier chaque partition
check_partition "$PART_BOOT" "Partition BOOT"
check_partition "$PART_SWAP" "Partition SWAP" 
check_partition "$PART_ROOT" "Partition ROOT"

# Afficher le schéma de partitionnement
info "Schéma de partitionnement détecté:"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT "$DISK"

# === Montage des partitions ===
info "Montage des partitions..."

# Nettoyage préalable
umount -R "$MNT" 2>/dev/null || true
mkdir -p "$MNT"

# Monter la partition root
info "Montage de $PART_ROOT sur $MNT..."
mount "$PART_ROOT" "$MNT" || err "Échec montage root"
ok "Root monté"

# Monter la partition boot
info "Montage de $PART_BOOT sur $MNT/boot..."
mkdir -p "$MNT$BOOT_DIR"
mount "$PART_BOOT" "$MNT$BOOT_DIR" || err "Échec montage boot"
ok "Boot monté"

# Activer le swap
info "Activation du swap $PART_SWAP..."
swapon "$PART_SWAP" && ok "Swap activé" || warn "Échec activation swap"

# === Montage des systèmes virtuels ===
info "Montage des systèmes de fichiers virtuels..."
for fs in dev sys proc run; do
    mkdir -p "$MNT/$fs"
    mount --rbind "/$fs" "$MNT/$fs" && mount --make-rslave "$MNT/$fs" && ok "/$fs monté" || warn "Échec montage /$fs"
done

# Copier resolv.conf
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null && ok "resolv.conf copié" || warn "resolv.conf non copié"

# === Vérification de l'environnement chroot ===
info "Vérification de l'environnement chroot..."
if [ -f "$MNT/etc/os-release" ]; then
    ok "Système Gentoo détecté:"
    grep PRETTY_NAME "$MNT/etc/os-release" | head -1
else
    warn "Fichier os-release non trouvé, mais continuation..."
fi

# === Installation GRUB dans chroot ===
info "Entrée dans l'environnement chroot..."

chroot "$MNT" /bin/bash -eux <<'CHROOT_EOF'
set -euo pipefail

# Fonctions couleurs
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[CHROOT]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[CHROOT OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[CHROOT WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[CHROOT ERROR]${NC} %s\n" "$*"; exit 1; }

export PS1="(chroot) \$ "

info "=== DÉBUT INSTALLATION GRUB ==="

# 1. Vérifier si GRUB est installé
if command -v grub-install >/dev/null 2>&1; then
    GRUB_VERSION=$(grub-install --version | head -1)
    ok "GRUB déjà installé: $GRUB_VERSION"
else
    info "Installation de GRUB..."
    if emerge --noreplace sys-boot/grub; then
        ok "GRUB installé avec succès"
    else
        err "Échec installation GRUB"
    fi
fi

# 2. Vérifier le mode (BIOS/UEFI)
if [ -d "/sys/firmware/efi" ]; then
    info "Mode UEFI détecté"
    INSTALL_MODE="uefi"
else
    info "Mode BIOS détecté"
    INSTALL_MODE="bios"
fi

# 3. Installation GRUB selon le mode
if [ "$INSTALL_MODE" = "uefi" ]; then
    info "Installation GRUB UEFI..."
    # Vérifier si /boot/efi existe et est monté
    if mountpoint -q /boot/efi; then
        ok "Partition EFI déjà montée"
    else
        warn "Partition EFI non montée, installation BIOS en fallback"
        INSTALL_MODE="bios"
    fi
    
    if [ "$INSTALL_MODE" = "uefi" ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || {
            warn "Échec installation UEFI, passage en mode BIOS"
            INSTALL_MODE="bios"
        }
    fi
fi

if [ "$INSTALL_MODE" = "bios" ]; then
    info "Installation GRUB BIOS sur /dev/sda..."
    if grub-install --target=i386-pc /dev/sda; then
        ok "GRUB installé dans le MBR"
    else
        err "Échec installation GRUB BIOS"
    fi
fi

# 4. Génération de grub.cfg
info "Génération de grub.cfg..."

# Sauvegarder l'ancien config si existant
[ -f /boot/grub/grub.cfg ] && cp /boot/grub/grub.cfg /boot/grub/grub.cfg.bak

# Générer le nouveau config
if grub-mkconfig -o /boot/grub/grub.cfg; then
    ok "grub.cfg généré avec succès"
else
    warn "Échec génération grub.cfg, création manuelle..."
    create_manual_grub_cfg
fi

# 5. Vérification finale
info "Vérification finale..."
echo "=== CONFIGURATION GRUB ==="
echo "Mode: $INSTALL_MODE"
echo "Disque: /dev/sda"
echo "Boot: /dev/sda1"
echo "Root: /dev/sda3"
echo "Swap: /dev/sda2"

if [ -f "/boot/grub/grub.cfg" ]; then
    ok "grub.cfg présent ($(stat -c%s /boot/grub/grub.cfg) octets)"
    info "Entrées de boot détectées:"
    grep "menuentry" /boot/grub/grub.cfg | head -3
else
    err "grub.cfg absent!"
fi

ok "✅ Installation GRUB terminée avec succès!"

# Fonction pour créer un grub.cfg manuel si nécessaire
create_manual_grub_cfg() {
    info "Création manuelle de grub.cfg..."
    mkdir -p /boot/grub
    cat > /boot/grub/grub.cfg << 'GRUB_EOF'
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro quiet
    initrd /initramfs
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro single
}

menuentry "Gentoo Linux (debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /vmlinuz root=/dev/sda3 ro debug
}
GRUB_EOF
    ok "grub.cfg manuel créé"
}

CHROOT_EOF

# === Vérification finale hors chroot ===
ok "Retour du chroot"
info "Vérifications finales..."

# Vérifier le MBR
info "Vérification du MBR..."
if dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    ok "✅ GRUB détecté dans le MBR"
else
    warn "⚠️  GRUB non détecté dans le MBR"
fi

# Vérifier grub.cfg
info "Vérification de grub.cfg..."
if [ -f "$MNT/boot/grub/grub.cfg" ]; then
    ok "✅ grub.cfg présent: $MNT/boot/grub/grub.cfg"
    echo "=== Extrait du grub.cfg ==="
    grep -A2 "menuentry" "$MNT/boot/grub/grub.cfg" | head -6
else
    err "❌ grub.cfg absent!"
fi

# Vérifier le noyau
info "Vérification du noyau..."
if ls "$MNT/boot/vmlinuz"* >/dev/null 2>&1; then
    ok "✅ Noyau présent:"
    ls -la "$MNT/boot/vmlinuz"*
else
    warn "⚠️  Aucun noyau trouvé dans /boot"
fi

# === Rapport final ===
echo ""
echo "================================================"
ok "🎉 INSTALLATION TERMINÉE AVEC SUCCÈS!"
echo "================================================"
echo ""
echo "📊 RÉSUMÉ DE VOTRE CONFIGURATION:"
echo ""
echo "   💾 DISQUE: $DISK"
echo "   🐧 BOOT:   $PART_BOOT → $MNT/boot"
echo "   🔄 SWAP:   $PART_SWAP"
echo "   📂 ROOT:   $PART_ROOT → $MNT"
echo ""
echo "✅ CE QUI A ÉTÉ INSTALLÉ:"
echo "   - GRUB dans le MBR de $DISK"
echo "   - Configuration GRUB dans /boot/grub/grub.cfg"
echo "   - Support BIOS pour le boot"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   umount -R $MNT"
echo "   swapoff $PART_SWAP"
echo "   reboot"
echo ""
echo "🔧 EN CAS DE PROBLÈME:"
echo "   - Au démarrage, appuyez sur 'c' pour entrer dans GRUB"
echo "   - Commandes manuelles:"
echo "     set root=(hd0,msdos1)"
echo "     linux /vmlinuz root=/dev/sda3 ro"
echo "     boot"
echo ""
warn "⚠️  N'OUBLIEZ PAS DE DÉMONTER AVANT DE REDÉMARRER!"