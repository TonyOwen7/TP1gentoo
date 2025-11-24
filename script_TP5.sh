#!/usr/bin/env bash
# prepare_chroot.sh
# Monte les partitions et prépare l'environnement chroot
# Usage: ./prepare_chroot.sh

set -euo pipefail

# Configuration
DISK="/dev/sda"
PART_ROOT="/dev/sda3"
PART_BOOT="/dev/sda1"
PART_HOME="/dev/sda4"
PART_SWAP="/dev/sda2"
MNT="/mnt/gentoo"
BOOT_DIR="/boot"

# Fonctions couleurs
info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }

# Monter root
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$PART_ROOT" "$MNT"
ok "Root mounted at $MNT"

# Monter boot
mkdir -p "$MNT$BOOT_DIR"
mountpoint -q "$MNT$BOOT_DIR" || mount "$PART_BOOT" "$MNT$BOOT_DIR"
ok "Boot mounted at $MNT$BOOT_DIR"

# Monter home si nécessaire
[ -b "$PART_HOME" ] && mkdir -p "$MNT/home" && mountpoint -q "$MNT/home" || mount "$PART_HOME" "$MNT/home" 2>/dev/null && ok "Home mounted"

# Activer swap
[ -b "$PART_SWAP" ] && swapon "$PART_SWAP" 2>/dev/null && ok "Swap active"

# Bind mounts
for fs in dev sys proc run; do
    mountpoint -q "$MNT/$fs" || mount --rbind "/$fs" "$MNT/$fs"
    mount --make-rslave "$MNT/$fs"
done
ok "Bind mounts done"

# Copier resolv.conf pour le réseau
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

info "Préparation chroot terminée. Maintenant, lancez le script grub_chroot.sh"
