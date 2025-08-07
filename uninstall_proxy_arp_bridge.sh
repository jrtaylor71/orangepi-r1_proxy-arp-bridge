#!/bin/bash

set -e

echo "=== Stopping parprouted service ==="
systemctl stop parprouted || true
systemctl disable parprouted || true
rm -f /etc/systemd/system/parprouted.service

echo "=== Removing networkd wait-online override ==="
rm -f /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
rmdir --ignore-fail-on-non-empty /etc/systemd/system/systemd-networkd-wait-online.service.d || true

echo "=== Restoring original Netplan config if backup exists ==="
latest_backup=$(ls -t /etc/netplan/armbian.yaml.bak.* 2>/dev/null | head -n1)
if [ -n "$latest_backup" ]; then
  echo "Restoring backup: $latest_backup"
  cp "$latest_backup" /etc/netplan/armbian.yaml
  netplan apply
else
  echo "No backup found. Leaving current Netplan config unchanged."
fi

echo "=== Re-enabling default Netplan DHCP config if previously disabled ==="
if [ -f /10-dhcp-all-interfaces.yaml.bak ]; then
  mv /10-dhcp-all-interfaces.yaml.bak /etc/netplan/10-dhcp-all-interfaces.yaml
fi

echo "=== Optionally removing parprouted and bridge-utils (prompting user) ==="
read -p "Do you want to remove 'parprouted' and 'bridge-utils'? [y/N] " remove_tools
if [[ "$remove_tools" =~ ^[Yy]$ ]]; then
  apt remove --purge -y parprouted bridge-utils
  apt autoremove -y
fi

echo "=== Reloading systemd and restarting networking ==="
systemctl daemon-reexec
systemctl daemon-reload
systemctl restart systemd-networkd
systemctl restart systemd-networkd-wait-online.service

echo "=== DONE ==="
echo "Reversed setup script. parprouted removed, Netplan restored (if backup existed)."
