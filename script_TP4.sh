#!/usr/bin/env bash
# tp1_mount_chroot.sh
# Montages, swap, bind mounts et préparation chroot pour Gentoo

set -euo pipefail

# Configuration
DISK="${DISK:-/dev/sda}"
PART_ROOT="${PART_ROOT:-/dev/sda3}"
PART_BOOT="${PART_BOOT:-/dev/sda1}"
PART_SWAP="${PART_SWAP:-/dev/sda2}"
PART_HOME="${PART_HOME:-/dev/sda4}"
MNT="${MNT:-/mnt/gentoo}"

# === Colors ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# Root check
[ "$(id -u)" -eq 0 ] || err "Run as root"

info "Mounting root partition..."
mkdir -p "$MNT"
mount "$PART_ROOT" "$MNT" 2>/dev/null || ok "$PART_ROOT already mounted"

info "Mounting boot partition..."
mkdir -p "$MNT/boot"
mount "$PART_BOOT" "$MNT/boot" 2>/dev/null || ok "$PART_BOOT already mounted"

# Optional mounts
[ -b "$PART_HOME" ] && mkdir -p "$MNT/home" && mount "$PART_HOME" "$MNT/home" 2>/dev/null || true
[ -b "$PART_SWAP" ] && swapon "$PART_SWAP" 2>/dev/null || true

# Bind mounts
for fs in dev sys proc run; do
    mount --rbind "/$fs" "$MNT/$fs" 2>/dev/null || true
    mount --make-rslave "$MNT/$fs" 2>/dev/null || true
done

# Copy resolv.conf
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

ok "Chroot environment ready at $MNT"
echo "Now run the chroot script: chroot $MNT /bin/bash /root/tp2_chroot_grub.sh"
