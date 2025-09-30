#!/usr/bin/env bash

echo "[*] Starting fix at $(date)"

# 1) Block service (re)starts to avoid kernel pssanics during postinst
echo "[*] Blocking systemd service starts..."
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
trap 'rm -f /usr/sbin/policy-rc.d' EXIT

# 2) Make sure ESP is mounted
echo "[*] Ensuring /boot/efi is mounted..."
if ! mountpoint -q /boot/efi; then
  mount /boot/efi || { echo "[!] Could not mount /boot/efi. Check fstab/ESP."; exit 1; }
fi
mount | grep -E '/boot/efi'

# 3) Tell grub postinst to avoid NVRAM, and also write removable path
echo "[*] Writing /etc/default/grub-installer with --no-nvram --removable..."
cat >/etc/default/grub-installer <<'EOG'
GRUB_INSTALL_EXTRA_ARGS="--no-nvram --removable"
EOG

# 4) Pre-install GRUB files into ESP without touching firmware NVRAM
echo "[*] Installing GRUB to ESP (no NVRAM)..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=proxmox --recheck --no-nvram --removable || true

echo "[*] Rebuilding grub.cfg..."
update-grub || true

# 5) Rebuild initramfs for current kernel (reduces configure failures)
KVER="$(uname -r)"
echo "[*] Rebuilding initramfs for ${KVER} ..."
update-initramfs -u -k "${KVER}" || true

# 6) Finish dpkg configuration with logging
echo "[*] Running dpkg --onfigure -a ..."
script -qc "dpkg --configure grub-efi-amd64 || true; dpkg --configure -a || true" ./dpkg-configure.log

echo "[*] Attempting apt repairs and finishing upgrade.."
apt --fix-broken install -y || true
apt update || true
apt full-upgrade -y || true

# 7) Rebuild grub one more time (now that packages are configured)
echo "[*] Final grub-install (no NVRAM) + update-grub..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=proxmox --recheck --no-nvram --removable || true
update-grub || true

# 8) Show current EFI entries (non-fatal if efibootmgr missing)
if command -v efibootmgr >/dev/null 2>&1; then
  echo "[*] efibootmgr -v:"
  efibootmgr -v || true
else
  echo "[i] efibootmgr not installed; skipping firmware entry dump."
fi

echo "[done] Finished. Logs saved to /root/fix_pve9_grub.log and /root/dpkg-configure.log"
echo "[i] You can reboot now. System will boot via \EFI\proxmox\grubx64.efi or fallback \EFI\BOT\BOOTX64.EFI."
