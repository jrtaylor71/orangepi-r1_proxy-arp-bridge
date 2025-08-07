#!/bin/bash

set -e

echo "=== Disabling default Netplan DHCP config ==="
if [ -f /etc/netplan/10-dhcp-all-interfaces.yaml ]; then
  mv /etc/netplan/10-dhcp-all-interfaces.yaml /10-dhcp-all-interfaces.yaml.bak
  echo "Moved 10-dhcp-all-interfaces.yaml to root to prevent DHCP conflicts."
fi

echo "=== Backing up existing Netplan config ==="
cp /etc/netplan/armbian.yaml /etc/netplan/armbian.yaml.bak.$(date +%Y%m%d%H%M%S)

echo "=== Writing updated Netplan config with wlan0 and bridged Ethernet ==="
cat <<EOF > /etc/netplan/armbian.yaml
network:
  version: 2
  renderer: networkd

  wifis:
    wlan0:
      optional: true
      addresses:
        - "192.168.55.100/24"
      nameservers:
        addresses:
          - 192.168.55.240
      dhcp4: false
      dhcp6: false
      macaddress: "WIFI_MAC_ADDRESS"
      routes:
        - metric: 200
          to: "0.0.0.0/0"
          via: "192.168.55.254"
      access-points:
        "camera555":
          auth:
            key-management: "psk"
            password: "YOUR_WIFI_PASSWORD"

  ethernets:
    end0:
      optional: true
    enxc0742bfff80b:
      optional: true

  bridges:
    br0:
      interfaces: [end0, enxc0742bfff80b]
      addresses: [192.168.55.99/24]
      dhcp4: false
      optional: true
EOF

echo "=== Applying Netplan ==="
netplan apply

echo "=== Installing parprouted and bridge-utils ==="
apt update
apt install -y parprouted bridge-utils

echo "=== Enabling IP forwarding ==="
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

echo "=== Creating parprouted systemd service with retry and forced NICs up ==="
cat <<EOF > /etc/systemd/system/parprouted.service
[Unit]
Description=Proxy ARP Routing Daemon (wlan0 <-> br0)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/bash -c 'ip link set end0 up; ip link set enxc0742bfff80b up; ip link set br0 up; until /usr/sbin/parprouted wlan0 br0; do sleep 5; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "=== Creating systemd override for wait-online ==="
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
cat <<EOF > /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --timeout=10 --ignore
EOF

echo "=== Reloading systemd and restarting services ==="
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable parprouted
systemctl start parprouted
systemctl restart systemd-networkd-wait-online.service

echo "=== DONE ==="
echo "Wi-Fi (wlan0) is 192.168.55.100. Ethernet bridge (br0) is 192.168.55.99. NICs forced up, parprouted runs in retry loop. Boot hangs are fixed."
