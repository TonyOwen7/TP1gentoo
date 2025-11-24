#!/usr/bin/env bash
# install_grub_safe.sh
# Safe, idempotent installer that mounts your Gentoo, chroots,
# installs GRUB to disk (MBR or UEFI), and generates grub.cfg.
#
# Usage: run as root from LiveCD:
#   chmod +x install_grub_safe.sh
#   ./install_grub_safe.sh
#
# Override defaults by editing the variables below if needed.

set -euo pipefail

### Configuration (edit if your layout differs) ###
DISK="${DISK:-/dev/sda}"     # disk (not a partition) for grub-install target
PART_BOOT="${PART_BOOT:-/dev/sda1}"
PART_SWAP="${PART_SWAP:-/dev/sda2}"
PART_ROOT="${PART_ROOT:-/dev/sda3}"
PART_HOME="${PART_HOME:-/dev/sda4}"
MNT="${MNT:-/mnt/gentoo}"
EFI_DIR="/boot/efi"          # used inside chroot for UEFI installs
BOOT_DIR="/boot"             # used inside chroot
GRUB_ID="${GRUB_ID:-Gentoo}" # EFI bootloader id
# End configuration

# Colors
BLUE='\033[1;34m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){ printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){ printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (from LiveCD)."
fi

info "Using disk: $DISK"
info "Root partition: $PART_ROOT"
info "Boot partition: $PART_BOOT"
info "Mount point: $MNT"

# Quick sanity: partitions exist?
for p in "$PART_ROOT" "$PART_BOOT"; do
  if [ ! -b "$p" ]; then
    err "Block device $p not found. Fix PART_* variables or attach device."
  fi
done

# 1) Mount target filesystem(s)
info "Mounting target partitions..."
mkdir -p "$MNT"
if mountpoint -q "$MNT"; then
  warn "$MNT already mounted — continuing (will reuse mounts)."
else
  mount "$PART_ROOT" "$MNT" || err "Failed to mount $PART_ROOT -> $MNT"
  ok "Mounted $PART_ROOT -> $MNT"
fi

# Ensure boot is mounted
mkdir -p "${MNT}${BOOT_DIR}"
if mountpoint -q "${MNT}${BOOT_DIR}"; then
  warn "${MNT}${BOOT_DIR} already mounted."
else
  mount "$PART_BOOT" "${MNT}${BOOT_DIR}" || warn "Could not mount $PART_BOOT to ${MNT}${BOOT_DIR} (continuing)"
  ok "Mounted $PART_BOOT -> ${MNT}${BOOT_DIR}"
fi

# Optional mounts
if [ -b "$PART_HOME" ]; then
  mkdir -p "${MNT}/home"
  if ! mountpoint -q "${MNT}/home"; then
    mount "$PART_HOME" "${MNT}/home" && ok "Mounted $PART_HOME -> ${MNT}/home" || warn "Couldn't mount $PART_HOME"
  fi
fi

if [ -b "$PART_SWAP" ]; then
  if ! swapon --show=NAME | grep -q "^$PART_SWAP\$"; then
    swapon "$PART_SWAP" 2>/dev/null && ok "Swap enabled $PART_SWAP" || warn "Could not enable swap $PART_SWAP"
  else
    ok "Swap already active: $PART_SWAP"
  fi
fi

# 2) Bind mount special filesystems
info "Preparing chroot bind mounts (proc/sys/dev/run)..."
mount -t proc proc "${MNT}/proc" 2>/dev/null || true
mount --rbind /sys "${MNT}/sys" 2>/dev/null || true
mount --make-rslave "${MNT}/sys" 2>/dev/null || true
mount --rbind /dev "${MNT}/dev" 2>/dev/null || true
mount --make-rslave "${MNT}/dev" 2>/dev/null || true
mount --rbind /run "${MNT}/run" 2>/dev/null || true
mount --make-slave "${MNT}/run" 2>/dev/null || true
ok "Bind mounts done."

# copy resolv.conf for network inside chroot
if [ -f /etc/resolv.conf ]; then
  cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf" || warn "Could not copy /etc/resolv.conf"
fi

# 3) Sanity checks before chroot
info "Sanity checks: kernel and /boot contents inside target..."
if ls "${MNT}${BOOT_DIR}/vmlinuz"* >/dev/null 2>&1; then
  ok "Kernel file(s) found in ${MNT}${BOOT_DIR}"
else
  warn "No kernel found in ${MNT}${BOOT_DIR}. grub-install may fail until kernel is installed."
fi

info "Listing block devices visible in current LiveCD:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# 4) Detect whether target expects UEFI vs BIOS
UEFI_POSSIBLE=false
# If the boot partition is vfat -> likely EFI system partition
if command -v blkid >/dev/null 2>&1; then
  FS_TYPE=$(blkid -o value -s TYPE "$PART_BOOT" 2>/dev/null || true)
  if [ -n "$FS_TYPE" ] && [ "$FS_TYPE" = "vfat" ]; then
    UEFI_POSSIBLE=true
    info "Detected FAT filesystem on $PART_BOOT -> will try UEFI install (efi dir ${EFI_DIR})."
  else
    info "Boot partition type: ${FS_TYPE:-unknown} (will default to BIOS install unless an EFI dir exists in chroot)."
  fi
else
  info "blkid not available; continuing with conservative defaults."
fi

# 5) Enter chroot and perform GRUB tasks there
info "Entering chroot and performing GRUB install steps..."

chroot "$MNT" /bin/bash -eux <<- 'CHROOT_EOF'
  set -euo pipefail
  export PS1="(chroot) $PS1"

  # helper functions (chroot output)
  info() { printf "\033[1;34m[CHROOT INFO]\033[0m %s\n" "$*"; }
  ok()   { printf "\033[1;32m[CHROOT OK]\033[0m %s\n" "$*"; }
  warn() { printf "\033[1;33m[CHROOT WARN]\033[0m %s\n" "$*"; }
  err()  { printf "\033[1;31m[CHROOT ERROR]\033[0m %s\n" "$*"; exit 1; }

  # Ensure basic tools exist (grub-install, grub-mkconfig, etc) or emerge them
  if ! command -v grub-install >/dev/null 2>&1; then
    info "GRUB not found inside chroot. Attempting emerge sys-boot/grub (may take time)..."
    if command -v emerge >/dev/null 2>&1; then
      emerge --noreplace sys-boot/grub || err "emerge sys-boot/grub failed"
      ok "grub emerged"
    else
      err "emerge not available inside chroot; cannot install GRUB package"
    fi
  else
    ok "grub binary present"
  fi

  # Decide whether to do UEFI or BIOS install:
  # UEFI logic: /boot/efi exists and is mounted (vfat), or /sys/firmware/efi exists (native)
  INSTALL_MODE="bios"
  if [ -d /boot/efi ] && mountpoint -q /boot/efi; then
    INSTALL_MODE="uefi"
    info "Detected /boot/efi mount -> using UEFI mode"
  elif [ -d /sys/firmware/efi ]; then
    INSTALL_MODE="uefi"
    info "Detected firmware EFI in chroot -> using UEFI mode"
  else
    info "No EFI detected -> using BIOS (i386-pc) mode"
  fi

  # GRUB install target and command
  if [ "$INSTALL_MODE" = "uefi" ]; then
    # make sure efivars mounted
    if ! mountpoint -q /sys/firmware/efi/efivars; then
      warn "efivars not mounted; UEFI install may fail if efivars are not available"
    fi
    # use variables provided by outer script via environment variables if set
    target_arg="--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo"
  else
    target_arg="--target=i386-pc"
  fi

  # Install grub to disk (disk is passed in via chroot environment $DISK)
  # Ensure /dev is usable and disk nodes exist
  if ! command -v grub-install >/dev/null 2>&1; then
    err "grub-install missing"
  fi

  info "Running grub-install. This writes to disk; ensure choice is correct."
  # Use the DISK variable exported into the chroot by the outer shell
  if grub-install ${DISK} ${target_arg} ; then
    ok "grub-install completed"
  else
    warn "Initial grub-install failed; attempting fallback options..."

    # Fallback attempts for BIOS installs
    if [ "$INSTALL_MODE" = "bios" ]; then
      grub-install --recheck ${DISK} && ok "grub-install --recheck succeeded" || warn "grub-install --recheck failed"
      if ! dd if=${DISK} bs=512 count=1 2>/dev/null | strings | grep -q GRUB; then
        warn "GRUB signature not found in MBR after attempts"
      fi
    else
      warn "UEFI install fallback not attempted automatically."
    fi
  fi

  # Generate grub.cfg using grub-mkconfig (if file not present or to refresh)
  if [ -f /boot/grub/grub.cfg ]; then
    info "Existing /boot/grub/grub.cfg found; backing up and regenerating."
    cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.old || true
  fi

  if grub-mkconfig -o /boot/grub/grub.cfg ; then
    ok "grub.cfg generated at /boot/grub/grub.cfg"
  else
    warn "grub-mkconfig failed; check kernel paths in /boot and configuration"
  fi

CHROOT_EOF

info "Returned from chroot."

# 6) Post-checks on host
info "Post-checks: verifying created files and MBR signature..."

if [ -f "${MNT}${BOOT_DIR}/grub/grub.cfg" ]; then
  ok "Found ${MNT}${BOOT_DIR}/grub/grub.cfg"
else
  warn "No grub.cfg found at ${MNT}${BOOT_DIR}/grub/grub.cfg"
fi

if dd if="$DISK" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
  ok "GRUB signature found in MBR of $DISK"
else
  warn "GRUB not detected in MBR of $DISK — the install may have been UEFI or failed"
fi

echo
ok "Script finished. If everything looks good, unmount and reboot when ready:"
cat <<EOF
  umount -R $MNT    # or selectively unmount bind mounts first
  swapoff $PART_SWAP 2>/dev/null || true
  reboot
EOF
