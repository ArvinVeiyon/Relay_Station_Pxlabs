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
| Service | Function |
|---|---|
| wifibroadcast@gs.service | WFB-NG ground station profile |
| ssh-tunnel-to-companion.service | autossh: port 2222 → drone 10.5.5.87:22 |
| mediamtx.service | Low-latency RTSP server (video relay to GCS) |
| isc-dhcp-server.service | DHCP server for 10.5.6.0/24 (range .50–.99) |
| netfilter-persistent.service | Persistent iptables rules |
| relay_files_sync.timer | Auto-backup of system files (boot + daily) |

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

## 7) MediaMTX (RTSP Video Relay)
- **Binary:** ~/Rtps_Server/mediamtx
- **Config:** ~/Rtps_Server/mediamtx.yml
- **Service:** mediamtx.service
- **Role:** Receives video from WFB-NG and re-streams to GCS (e.g. QGroundControl)

## 8) DHCP Server
- **Service:** isc-dhcp-server.service
- **Config:** /etc/dhcp/dhcpd.conf
- **Subnet:** 10.5.6.0/24
- **Range:** 10.5.6.50 – 10.5.6.99
- **Router:** 10.5.6.1

## 9) Local Scripts
| Script | Location | Function |
|---|---|---|
| rely_p2p.sh | ~/rely_p2p.sh | P2P WiFi setup |
| start_p2p_on_wlan0.sh | ~/start_p2p_on_wlan0.sh | P2P on wlan0 |
| bg10_producer_rgb.py | /usr/local/bin/ | Camera raw frame producer |
| wfbng_install.sh | ~/ | WFB-NG install script |

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

## Auto Sync Log

## 13) WFB-NG Cluster Mode (Distributed Network)

The relay can run in two modes — switch by starting/stopping different systemd services:

### Mode A — Standalone (default)
Single GS node, only the relay's WiFi adapter:
```bash
sudo systemctl stop wifibroadcast-cluster@gs.service
sudo systemctl start wifibroadcast@gs.service
```
- Service: `wifibroadcast@gs.service`
- Uses: `--wlans wlx00c0cab6db3b`

### Mode B — Cluster (distributed, adds OpenWrt node)
Two RF nodes: relay (wlx00c0cab6db3b) + OpenWrt CPE610 (10.5.7.102, phy0-mon0):
```bash
sudo systemctl stop wifibroadcast@gs.service
sudo systemctl start wifibroadcast-cluster@gs.service
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
