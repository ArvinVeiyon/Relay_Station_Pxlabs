#!/bin/bash
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -C /var/run/wpa_supplicant
sudo wpa_cli -i wlan0 p2p_group_add persistent=0
sleep 5
sudo ifconfig p2p-wlan0-0 10.5.6.101 netmask 255.255.255.0 up
sudo wpa_cli -i p2p-wlan0-0 wps_pin any 1987
sleep 5
#sudo iptables -A FORWARD -i p2p-wlan0-0 -o eth0 -j ACCEPT
#sudo iptables -A FORWARD -i eth0 -o p2p-wlan0-0 -j ACCEPT

# 1) Remove proto-kernel routes if they exist
#sudo ip route del 10.5.6.0/24 dev eth0        2>/dev/null || true
#sudo ip route del 10.5.6.0/24 dev p2p-wlan0-0 2>/dev/null || true

# 2) Add routes with correct priority & src IPs
#sudo ip route add 10.5.6.0/24 dev eth0        scope link src 10.5.6.100 metric 50
#sudo ip route add 10.5.6.0/24 dev p2p-wlan0-0 scope link src 10.5.6.101 metric 200
