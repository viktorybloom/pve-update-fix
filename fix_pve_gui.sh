#!/usr/bin/env bash
set -euo pipefail
[ -f /usr/sbin/policy-rc.d ] && rm -f /usr/sbin/policy-rc.d
for s in pveproxy pvedaemon pvestatd pve-ha-lrm pve-ha-crm pve-cluster; do
  systemctl unmask "$s" >/dev/null 2>&1 || true
done
systemctl daemon-reload
mount | grep -q "/boot/efi" || mount /boot/efi || true
df -T /etc/pve || true
systemctl enable --now pve-cluster || true
systemctl restart pve-cluster || true
sleep 2
pvecm updatecerts -f || true
systemctl enable --now pveproxy pvedaemon pvestatd || true
systemctl --no-pager --full status pveproxy | sed -n '1,80p' || true
ss -ltnp | grep -E '8006|pveproxy' || true
if command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 8006/tcp || true
  fi
fi
