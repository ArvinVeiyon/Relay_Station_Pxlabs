# Relay Station — System Reference (vind-rly)

## 1) Hardware
- **Board:** Raspberry Pi 5
- **Hostname:** vind-rly
- **OS:** Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel:** 6.8.0-1018-raspi (aarch64)
- **Role:** WFB-NG ground station relay + SSH tunnel to drone companion

## 2) Network Interfaces
| Interface | IP | Role |
|---|---|---|
| eth0 | — | Ethernet (no carrier) |
| wlan0 | — | Onboard WiFi (unused) |
| wlx00c0cab6db3b | — | WFB-NG WiFi adapter (rtl8812eu) |
| p2p-wlan0-0 | 10.5.6.101/24 | P2P WiFi — ground station LAN |
| gs-wfb | 10.5.5.77/24 | WFB-NG tunnel to drone (10.5.5.87) |

## 3) Key Services
| Service | Status | Function |
|---|---|---|
| wifibroadcast@gs.service | ACTIVE | WFB-NG ground station profile (standalone mode) |
| mavlink.router.service | ACTIVE | MAVLink routing WFB→QGC + antenna tracker |
| ssh-tunnel-to-companion.service | ACTIVE | autossh: port 2222 → drone 10.5.5.87:22 |
| relay_files_sync.timer | ACTIVE | Auto-backup of system files (boot + daily) |
| mediamtx.service | DISABLED | RTSP video relay — disabled 2026-03-15 (latency) |
| isc-dhcp-server.service | DISABLED | DHCP for 10.5.6.0/24 — disabled 2026-03-15 (GCS uses static IP 10.5.6.50) |
| netfilter-persistent.service | present | Persistent iptables rules |

## 4) Ports
| Port | Service |
|---|---|
| 22 | SSH (relay itself) |
| 2222 | SSH tunnel → drone companion (10.5.5.87:22) |
| 8003 | WFB-NG stats |
| 8103 | WFB-NG API |

## 5) SSH Tunnel Detail
- **Service:** ssh-tunnel-to-companion.service
- **Command:** autossh -M 0 -L 0.0.0.0:2222:10.5.5.87:22 roz@10.5.5.87 -N -i /home/vind-admin/.ssh/id_rsa
- **Usage:** ssh -p 2222 roz@10.5.5.77 (or 10.5.6.101) → connects to drone companion
- **Key used:** /home/vind-admin/.ssh/id_rsa (must be authorized on drone)

## 6) WFB-NG Configuration
- **Config:** /etc/wifibroadcast.cfg
- **Profile:** gs (ground station)
- **WiFi channel:** 157 (5 GHz), region BO, TX power 30 dBm (rtl8812eu)
- **MCS:** 1, BW 20 MHz
- **Keys:** /etc/gs.key, /etc/drone.key
- **Cluster:** 10.5.7.102 (second node, phy0-mon0)
- **GS tunnel IP:** 10.5.5.77/24

## 7) MediaMTX (RTSP Video Relay) — DISABLED 2026-03-15
- **Binary:** ~/Rtps_Server/mediamtx
- **Config:** ~/Rtps_Server/mediamtx.yml
- **Service:** mediamtx.service (disabled — caused latency issues)
- **Role:** Was re-streaming WFB-NG video to GCS — replaced by direct WFB-NG GS endpoint

## 8) DHCP Server — DISABLED 2026-03-15
- **Service:** isc-dhcp-server.service (disabled — GCS uses static IP 10.5.6.50)
- **Config:** /etc/dhcp/dhcpd.conf
- **Subnet:** 10.5.6.0/24
- **Range:** 10.5.6.50 – 10.5.6.99
- **Router:** 10.5.6.1

## 9) Local Scripts & Control Tools
| Script | Location | Function |
|---|---|---|
| wfb-rlyctl | /usr/local/sbin/wfb-rlyctl | WFB-NG relay control: mode switch, NIC config, restart |
| rely_p2p.sh | ~/rely_p2p.sh | P2P WiFi setup |
| start_p2p_on_wlan0.sh | ~/start_p2p_on_wlan0.sh | P2P on wlan0 |
| bg10_producer_rgb.py | /usr/local/bin/ | Camera raw frame producer |
| wfbng_install.sh | ~/ | WFB-NG install script |

### wfb-rlyctl usage
```bash
wfb-rlyctl status                  # show current mode, ENV, service states
wfb-rlyctl list-nics               # list available wireless interfaces
sudo wfb-rlyctl use-standalone     # switch to standalone mode (wifibroadcast@gs)
sudo wfb-rlyctl use-cluster        # switch to cluster mode (wifibroadcast-cluster@gs)
sudo wfb-rlyctl set-nics <iface>   # update WFB_NICS in /etc/default/wifibroadcast + restart
sudo wfb-rlyctl restart            # restart active standalone service
```
Sudoers: `/etc/sudoers.d/wfb-rlyctl` (passwordless sudo scoped to this script)

## 10) Source Repos (built locally)
| Project | Location | Remote |
|---|---|---|
| wfb-ng | ~/wfb-ng | github.com/svpcom/wfb-ng |
| mavlink-router | ~/mavlink-router | github.com/mavlink-router/mavlink-router |
| rtl8812au driver | ~/rtl8812au | — |
| rtl8812eu driver | ~/rtl8812eu | — |

## 11) Users
| User | UID | Role |
|---|---|---|
| vind-gs | 1000 | Ground station user |
| vind-admin | 1001 | Admin user (main login) |

## 12) Auto-Backup
- **Repo:** ~/codex-relay
- **Script:** ~/codex-relay/scripts/system_files_sync.sh
- **Timer:** relay_files_sync.timer (boot + daily)
- **Tracked files:** System_files_list.txt

## 8) Install + Recovery Runbook

Current access path:
- Relay reachable via WFB tunnel IP `10.5.5.77` (from drone side)
- Relay direct LAN/Wi-Fi management IP may change during WPA/P2P setup
- When relay uses the same adapter for WPA/P2P and other links, temporary disconnect can happen

Target behavior:
- Relay acts as GS bridge for WFB-NG
- Ground systems (QGC or any OS) connect to relay management SSH on `:22`
- Ground systems connect to drone SSH through relay on `:2222`

Critical rule:
- In `/etc/wifibroadcast.cfg` keep `[gs_tunnel] default_route = False`
- Do not set tunnel default route to true in this mixed-network setup

### Safe implementation order
1. Prepare base packages: `wpasupplicant wireless-tools net-tools dnsmasq openssh-server autossh socat`
2. Configure WFB first and verify tunnel still works (drone: `10.5.5.87`, relay: `10.5.5.77`)
3. Configure relay management network (LAN/Wi-Fi) with static plan
4. Configure WPA/P2P only after confirming fallback access path
5. Add boot services (ssh, WFB, relay P2P, tunnel service)
6. Reboot once and validate all paths

### WPA/P2P baseline
`/etc/wpa_supplicant/wpa_supplicant.conf`:
- `ctrl_interface=/var/run/wpa_supplicant GROUP=netdev`
- `update_config=1`
- `device_name=VIND_RLY_P2P`

P2P startup commands:
```bash
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -C /var/run/wpa_supplicant
wpa_cli -i wlan0 p2p_group_add persistent=0
ifconfig p2p-wlan0-0 10.5.6.101 netmask 255.255.255.0 up
wpa_cli -i p2p-wlan0-0 wps_pin any 1987
```

### Drone SSH bridge through relay
- Listen: relay management IP `:2222`
- Target: `10.5.5.87:22` (drone over WFB tunnel)
- Backend: autossh systemd service (`ssh-tunnel-to-companion.service`)

### Validation checklist
1. `ip -br a` shows `gs-wfb` with `10.5.5.77/24`
2. `ping 10.5.5.87` succeeds from relay
3. `systemctl status wifibroadcast@gs.service` is active
4. `ss -tulpen | grep 2222` shows listener on relay
5. Ground station SSH drone via relay: `ssh <user>@<relay_mgmt_ip> -p 2222`

### Recovery when relay disconnects mid-setup
1. Re-enter relay through tunnel path (`10.5.5.77`)
2. Stop temporary P2P: `sudo pkill -f "wpa_supplicant.*wlan0"`
3. Restore known-good WFB config: ensure `[gs_tunnel] default_route = False`
4. `sudo systemctl restart wifibroadcast@gs.service`
5. Confirm `ping 10.5.5.87` before reattempting WPA/P2P

---

## 9) MAVLink Router + Antenna Tracker

### mavlink-router (IMPLEMENTED 2026-03-15)
WFB-NG `gs_mavlink` peer redirected from direct QGC to local mavlink-router.
Distributes to both QGC and antenna tracker — no ROS2/DDS, zero tunnel overhead.

**`/etc/wifibroadcast.cfg`:**
```ini
[gs_mavlink]
peer = 'connect://127.0.0.1:14560'   # was connect://10.5.6.50:14550
```

**`/etc/mavlink-router/main.conf`:**
```ini
[General]
TcpServerPort=5760

[UdpEndpoint WFB-input]
Mode=server
Address=0.0.0.0
Port=14560

[UdpEndpoint QGC]
Mode=normal
Address=10.5.6.50
Port=14550

[UdpEndpoint tracker]
Mode=normal
Address=127.0.0.1
Port=14551
```

Service: `mavlink.router.service` — enabled and running.
- QGC receives MAVLink on `10.5.6.50:14550` unchanged
- Antenna tracker reads from `127.0.0.1:14551`

### Antenna Tracker (TODO — hardware pending)
- Read `GLOBAL_POSITION_INT` from `127.0.0.1:14551`
- Relay fixed GPS → calculate bearing + elevation to drone (Haversine)
- Output to rotator controller via GPIO or serial
- Pure Python/pymavlink — no ROS2 (avoids DDS multicast flooding WFB tunnel)

### Notes
- Always confirm current reachable relay IP before making network changes
- Prefer applying one network subsystem at a time (WFB → management LAN → P2P)
- Avoid enabling competing managers on same interface during bring-up

## Auto Sync Log

## 13) WFB-NG Cluster Mode (Distributed Network)

The relay can run in two modes — switch by starting/stopping different systemd services:

### Mode A — Standalone (default) ← CURRENT
Single GS node, only the relay's WiFi adapter:
```bash
sudo wfb-rlyctl use-standalone
```
- Service: `wifibroadcast@gs.service`
- Uses: `--wlans wlx00c0cab6db3b`

### Mode B — Cluster (distributed, adds OpenWrt node)
Two RF nodes: relay (wlx00c0cab6db3b) + OpenWrt CPE610 (10.5.7.102, phy0-mon0):
```bash
sudo wfb-rlyctl use-cluster
```
- Service: `wifibroadcast-cluster@gs.service`
- Uses: `wfb-server --profiles gs --cluster ssh` (WFB_CLUSTER_MODE in env)
- Cluster config in `/etc/wifibroadcast.cfg` → `[cluster]` section
- Nodes: `127.0.0.1` (relay) + `10.5.7.102` (OpenWrt CPE610)
- SSH key: `/home/vind-admin/.ssh/wfb_cluster_ed25519` (used to init OpenWrt node)

### Cluster Init (first time or after OpenWrt reflash)
```bash
sudo wfb-server --profiles gs --gen-init 10.5.6.102 > /tmp/cpe610_node_init.sh
scp -O -i ~/.ssh/wfb_cluster_ed25519 /tmp/cpe610_node_init.sh root@10.5.6.102:/tmp/
ssh -i ~/.ssh/wfb_cluster_ed25519 root@10.5.6.102 'bash /tmp/cpe610_node_init.sh'
```

### OpenWrt Node (CPE610)
- **Device:** TP-Link CPE610 v2
- **Firmware:** openwrt-24.10.4-ath79-generic-tplink_cpe610-v2 (in ~/Openwrt_WFB_NG/)
- **WFB-NG package:** wfb-ng_24.9.7-r2_mips_24kc.ipk (in ~/Openwrt_WFB_NG/)
- **IP:** 10.5.7.102 (when cluster active)
- **WFB iface:** phy0-mon0
- **Custom init script on node:** /usr/sbin/wfb-mon0.sh
- **SSH:** root@10.5.7.102 via wfb_cluster_ed25519 key

### Cluster vs Standalone Summary
| | Standalone | Cluster |
|---|---|---|
| Service | wifibroadcast@gs | wifibroadcast-cluster@gs |
| RF nodes | 1 (relay RPi) | 2 (RPi + CPE610) |
| Coverage | Single antenna | Distributed/wider |
| Mode flag | --wlans | --cluster ssh |
**2026-02-22 18:48**
- A	System_files/etc/mavlink-router/main.conf
- A	System_files/etc/sid.conf
- A	System_files/etc/systemd/system/mavlink.router.service
- M	System_files/etc/wifibroadcast.cfg
- M	System_files_list.txt
**2026-03-15 18:18**
- M	System_files/etc/sid.conf
**2026-03-15 18:47**
- M	System_files/etc/sid.conf
**2026-03-15 18:55**
- A	System_files/etc/netplan/50-cloud-init.yaml
