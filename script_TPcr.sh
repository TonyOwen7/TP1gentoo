#!/usr/bin/env bash
# prepare_chroot.sh
# Prépare Gentoo pour chroot sans lancer directement chroot

set -euo pipefail

# === Configuration ===
DISK="${DISK:-/dev/sda}"
PART_BOOT="${PART_BOOT:-/dev/sda1}"
PART_ROOT="${PART_ROOT:-/dev/sda3}"
PART_HOME="${PART_HOME:-/dev/sda4}"
PART_SWAP="${PART_SWAP:-/dev/sda2}"
MNT="${MNT:-/mnt/gentoo}"

# === Couleurs ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# === Root check ===
[ "$(id -u)" -eq 0 ] || err "Run as root"

# === Vérification des partitions ===
for p in "$PART_ROOT" "$PART_BOOT"; do
    [ -b "$p" ] || err "Block device $p not found"
done

info "Root: $PART_ROOT, Boot: $PART_BOOT, Home: $PART_HOME"

# === Démonter si monté ===
umount -R "$MNT" 2>/dev/null || true
swapoff "$PART_SWAP" 2>/dev/null || true

# === Monter partitions ===
mkdir -p "$MNT"
mount "$PART_ROOT" "$MNT" || err "Failed to mount root"

mkdir -p "$MNT/boot"
mount "$PART_BOOT" "$MNT/boot" || ok "Boot already mounted"

if [ -b "$PART_HOME" ]; then
    mkdir -p "$MNT/home"
    mount "$PART_HOME" "$MNT/home" || ok "Home already mounted"
fi

if [ -b "$PART_SWAP" ]; then
    swapon "$PART_SWAP" 2>/dev/null || warn "Could not enable swap"
fi

# === Bind mounts pour chroot ===
for fs in proc sys dev run; do
    mount --rbind "/$fs" "$MNT/$fs" 2>/dev/null || true
    mount --make-rslave "$MNT/$fs" 2>/dev/null || true
done
ok "Bind mounts proc/sys/dev/run prêts"

# === Copie resolv.conf pour réseau dans chroot ===
if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" || warn "Cannot copy resolv.conf"
fi

info "Prêt pour chroot. Lancez maintenant manuellement :"
echo "chroot $MNT /bin/bash"
