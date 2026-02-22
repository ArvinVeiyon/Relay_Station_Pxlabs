#!/bin/bash
set -e

echo "🔄 Cleaning wlan0..."
sudo ip link set wlan0 down
sudo ip addr flush dev wlan0
sleep 1
sudo ip link set wlan0 up

echo "📡 Creating P2P group via systemd-managed wpa_supplicant..."
sudo wpa_cli -i wlan0 p2p_group_add persistent=0
sleep 3

P2P_IF=$(ip link | grep -o "p2p-wlan0-[0-9]*" | head -n 1)
if [ -z "$P2P_IF" ]; then
    echo "❌ Failed to detect P2P interface"
    exit 1
fi

echo "✅ P2P interface created: $P2P_IF"
sudo ifconfig "$P2P_IF" 10.5.6.101 netmask 255.255.255.0 up

echo "🔑 Enabling WPS PIN mode with PIN 1987..."
sudo wpa_cli -i "$P2P_IF" wps_pin any 1987

echo "🎉 P2P is ready on $P2P_IF"
