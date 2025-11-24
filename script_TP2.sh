#!/usr/bin/env bash
# safe_grub_install.sh
# Idempotent GRUB installer for Gentoo (BIOS or UEFI)

set -euo pipefail

# CONFIGURATION
DISK="${DISK:-/dev/sda}"
PART_BOOT="${PART_BOOT:-/dev/sda1}"
PART_ROOT="${PART_ROOT:-/dev/sda3}"
PART_HOME="${PART_HOME:-/dev/sda4}"
PART_SWAP="${PART_SWAP:-/dev/sda2}"
MNT="${MNT:-/mnt/gentoo}"
BOOT_DIR="/boot"
EFI_DIR="/boot/efi"
GRUB_ID="${GRUB_ID:-Gentoo}"

# Colors
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# REQUIRE ROOT
[ "$(id -u)" -ne 0 ] && err "Run as root (from LiveCD)"

# SANITY CHECKS
for p in "$PART_ROOT" "$PART_BOOT"; do
    [ ! -b "$p" ] && err "Block device $p not found"
done

# MOUNT ROOT AND BOOT
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$PART_ROOT" "$MNT" || err "Failed mounting $PART_ROOT"

mkdir -p "${MNT}${BOOT_DIR}"
mountpoint -q "${MNT}${BOOT_DIR}" || mount "$PART_BOOT" "${MNT}${BOOT_DIR}" || warn "Could not mount boot"

# Optional: mount home & enable swap
[ -b "$PART_HOME" ] && mkdir -p "${MNT}/home" && mountpoint -q "${MNT}/home" || mount "$PART_HOME" "${MNT}/home" || true
[ -b "$PART_SWAP" ] && ! swapon --show=NAME | grep -q "^$PART_SWAP\$" && swapon "$PART_SWAP" || true

# Bind mounts for chroot
for fs in proc sys dev run; do
    mountpoint -q "${MNT}/${fs}" || mount --rbind /$fs "${MNT}/${fs}" && mount --make-rslave "${MNT}/${fs}" || true
done

# Copy resolv.conf for networking
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf" || warn "No resolv.conf"

# KERNEL CHECK
if ls "${MNT}${BOOT_DIR}/vmlinuz"* >/dev/null 2>&1; then
    ok "Kernel(s) found in $BOOT_DIR"
else
    warn "No kernel found; grub-install may fail until kernel installed"
fi

# Detect UEFI
UEFI=false
FS_TYPE=$(blkid -o value -s TYPE "$PART_BOOT" 2>/dev/null || echo "")
[ "$FS_TYPE" = "vfat" ] && UEFI=true && info "Detected EFI boot partition (vfat)"

# ENTER CHROOT
info "Entering chroot for GRUB install..."
chroot "$MNT" /bin/bash -eux <<- 'CHROOT_EOF'
    set -euo pipefail
    export PS1="(chroot) \$ "

    info() { printf "\033[1;34m[CHROOT INFO]\033[0m %s\n" "$*"; }
    ok()   { printf "\033[1;32m[CHROOT OK]\033[0m %s\n" "$*"; }
    warn() { printf "\033[1;33m[CHROOT WARN]\033[0m %s\n" "$*"; }
    err()  { printf "\033[1;31m[CHROOT ERROR]\033[0m %s\n" "$*"; exit 1; }

    # Install grub if missing
    command -v grub-install >/dev/null 2>&1 || (emerge --noreplace sys-boot/grub || err "Failed installing GRUB")

    # Determine BIOS vs UEFI
    INSTALL_MODE="bios"
    [ -d /boot/efi ] && mountpoint -q /boot/efi && INSTALL_MODE="uefi"
    [ -d /sys/firmware/efi ] && INSTALL_MODE="uefi"

    info "Install mode: $INSTALL_MODE"

    if [ "$INSTALL_MODE" = "uefi" ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || warn "UEFI grub-install failed"
    else
        grub-install --target=i386-pc --recheck /dev/sda || warn "BIOS grub-install failed"
    fi

    # Generate grub.cfg
    [ -f /boot/grub/grub.cfg ] && cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.bak || true
    grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed"

CHROOT_EOF

ok "Returned from chroot. GRUB install attempted."

# POST-CHECK
[ -f "${MNT}${BOOT_DIR}/grub/grub.cfg" ] && ok "grub.cfg exists" || warn "grub.cfg missing"

info "Finished. Unmount and reboot when ready:"
cat <<EOF
umount -R $MNT
swapoff $PART_SWAP 2>/dev/null || true
reboot
EOF
