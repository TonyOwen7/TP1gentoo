#!/usr/bin/env bash
# tp2_chroot_grub.sh
# Installe GRUB et génère grub.cfg dans le chroot

set -euo pipefail

# === Colors ===
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# Ensure PS1 set
export PS1="(chroot) $PS1"

# Start udev for BIOS detection
[ -x /etc/init.d/udev ] && /etc/init.d/udev start || warn "udev start failed"

# Install GRUB if missing
if ! command -v grub-install >/dev/null 2>&1; then
    info "Installing GRUB..."
    [ -x /usr/bin/emerge ] && emerge --noreplace sys-boot/grub || err "GRUB not found and cannot install"
else
    ok "GRUB present"
fi

# Detect BIOS/UEFI
INSTALL_MODE="bios"
[ -d /boot/efi ] && mountpoint -q /boot/efi && INSTALL_MODE="uefi"
[ -d /sys/firmware/efi ] && INSTALL_MODE="uefi"
info "Detected GRUB install mode: $INSTALL_MODE"

# Run grub-install
if [ "$INSTALL_MODE" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || warn "UEFI grub-install failed"
else
    grub-install --target=i386-pc /dev/sda || err "BIOS grub-install failed"
fi
ok "grub-install done"

# Generate grub.cfg
[ -f /boot/grub/grub.cfg ] && cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg generated"
