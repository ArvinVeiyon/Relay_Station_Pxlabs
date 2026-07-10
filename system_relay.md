# Relay Station — System Reference (vind-rly)

## 1) Hardware
- **Board:** Raspberry Pi 5
- **Hostname:** vind-rly
- **User:** vind-admin (admin login) | vind-gs (GS user)
- **SSH:** `ssh vind-admin@10.5.5.77`
- **OS:** Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel:** 6.8.0-1018-raspi (aarch64)
- **Role:** WFB-NG ground station relay + SSH tunnel to drone companion

## 2) Network Interfaces
| Interface | IP | Role |
|---|---|---|
| eth0 | — | Ethernet — used to connect CPE610 OpenWrt node for WFB-NG cluster mode |
| wlan0 | — | Onboard WiFi — P2P group owner for ground station PC connection |
| wlx00c0cab6db3b | — | WFB-NG RF adapter (rtl8812eu) — air link to drone |
| p2p-wlan0-0 | 10.5.6.101/24 | P2P WiFi interface — ground station LAN |
| gs-wfb | 10.5.5.77/24 | WFB-NG tunnel to drone (10.5.5.87) |

### Ground Station (GCS)
- **GCS IP:** 10.5.6.50 (static — QGroundControl PC on p2p-wlan0-0 LAN)
- **Video:** WFB-NG `gs_video` → `connect://10.5.6.50:5600`
- **MAVLink:** mavlink-router → QGC `10.5.6.50:14550` (via WFB-NG gs_mavlink→127.0.0.1:14560)
- **SSH to drone via relay:** `ssh -p 2222 roz@10.5.5.77`

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

Config file: `/etc/wifibroadcast.cfg` | Profile used: **gs** (ground station)
Relay runs only the `gs` profile — never `drone`. The `[drone]` section in the config is present for reference only.

> **⚠ History warning:** On 2026-02-22, the `[cluster]` section was accidentally wiped during
> a mavlink-router setup session. Someone edited the live config and replaced it with an empty
> template. The auto-sync committed the wiped state. All tags from v1.0.0 to v1.0.2 had the
> empty cluster section. Fixed 2026-07-10 (v1.0.3). If cluster mode ever breaks with
> `Cluster is empty!` — this section was wiped again. Restore from below.

### RF Settings
| Parameter | Value | Notes |
|---|---|---|
| `wifi_channel` | 161 | 5 GHz — matches drone side exactly |
| `wifi_region` | BO | Bolivia — allows higher TX power |
| `wifi_txpower` | 3000 | 30 dBm × 100 (rtl8812eu driver unit) |
| `bandwidth` | 20 MHz | 20 MHz channel width |
| `mcs_index` | 1 | BPSK 1/2 — robust low-rate modulation |
| `stbc` | 1 | Space-time block coding enabled |
| `ldpc` | 1 | Low-density parity check enabled |
| `short_gi` | False | Standard guard interval |

### Modes
| Mode | Service | Command |
|---|---|---|
| Standalone (default) | `wifibroadcast@gs.service` | `sudo wfb-rlyctl use-standalone` |
| Cluster (+CPE610) | `wifibroadcast-cluster@gs.service` | `sudo wfb-rlyctl use-cluster` |

### GS Profile Streams
| Stream | Direction | Stream ID | Service type | Peer |
|---|---|---|---|---|
| video | RX only | 0x00 | `udp_direct_rx` | → `connect://10.5.6.50:5600` (GCS) |
| mavlink | RX 0x10 / TX 0x90 | — | `mavlink` | → `connect://127.0.0.1:14560` (mavlink-router) |
| tunnel | RX 0x20 / TX 0xa0 | — | `tunnel` | ifname `gs-wfb` @ `10.5.5.77/24` |

> **mavlink peer is `127.0.0.1:14560`** (local mavlink-router), NOT direct to QGC.
> mavlink-router then routes to QGC (`10.5.6.50:14550`) + antenna tracker (`127.0.0.1:14551`).
> `default_route = False` on gs_tunnel — critical, do not change.

### Cluster Section — Full Reference Config
> This is the correct populated cluster section. Keep this here as the restore reference.
> The only bug in the original (2695911 initial commit) was `ssh_key` pointing to `/root/.ssh/`
> instead of `/home/vind-admin/.ssh/` — corrected here.

```ini
[cluster]
# Two nodes: relay's own NIC (127.0.0.1) + CPE610 OpenWrt node (10.5.7.102)
# wlx00c0cab6db3b = relay's RTL8812EU WiFi adapter (wlan side)
# phy0-mon0       = CPE610's monitor-mode interface, initialized via wfb-mon0.sh
nodes = {'127.0.0.1': {'wlans': ['wlx00c0cab6db3b']}, '10.5.7.102': {'wlans': ['phy0-mon0'],'wifi_txpower': None,'custom_init_script': '/usr/sbin/wfb-mon0.sh'}}

ssh_user = 'root'           # CPE610 is OpenWrt — root user
ssh_port = 22               # standard SSH port on CPE610
ssh_key  = '/home/vind-admin/.ssh/wfb_cluster_ed25519'   # NOT /root/.ssh/ — vind-admin owns key
server_address = '10.5.7.100'   # relay's own eth0 IP — CPE610 connects BACK to this
base_port_server = 10000    # relay listens on these ports for CPE610 data
base_port_node   = 11000    # CPE610 listens on these for relay data
api_port  = 8203
stats_port = 8303
```

**Parameter meanings:**
| Parameter | Meaning |
|---|---|
| `nodes` | Dict of cluster nodes: key=address, value=NIC config |
| `127.0.0.1` | Relay itself — uses its local WFB adapter |
| `10.5.7.102` | CPE610 — reached via relay eth0 (10.5.7.0/24 subnet) |
| `custom_init_script` | Script on CPE610 that puts phy0 into monitor mode for WFB-NG |
| `ssh_key` | Ed25519 key for relay→CPE610 SSH (root@10.5.7.102) |
| `server_address` | Relay's eth0 IP — CPE610 opens connections BACK to relay on this |
| `base_port_server` | Base port for relay's RX/TX servers (mavlink=10001, tunnel=10002) |
| `base_port_node` | Base port for CPE610's RX/TX (mavlink=11001, tunnel=11002) |

**Verify cluster is working:**
```bash
sudo wfb-rlyctl use-cluster
sudo journalctl -u wifibroadcast-cluster@gs.service -f
# Should NOT see "Cluster is empty!" — should see wfb_tx processes connecting to 10.5.7.102
ps aux | grep wfb_tx   # should show 10.5.7.102 in args
```

### Network
- WFB adapter: `wlx00c0cab6db3b` (RTL8812EU)
- GS tunnel interface: `gs-wfb` @ `10.5.5.77/24`
- Cluster eth0: `10.5.7.100/24` (relay ↔ CPE610 at `10.5.7.102`)
- Keys: `/etc/gs.key` + `/etc/drone.key`

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

> **No internet on relay** — `codex-relay` has no configured remote and relay cannot reach GitHub.
> All pushes to GitHub (`ArvinVeiyon/Relay_Station_Pxlabs`) must be done via the companion mirror:
> `~/codex-relay-mirror` on Vind-Roz → fetch from relay via SSH → push to GitHub.

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

## 14) GCS Interface — G-Control (PXLABS QGC)

G-Control (ArvinVeiyon/PXLABS_qgroundcontrol, branch: master) controls the relay directly via SSH,
separate from the companion SSH tunnel.

### Relay SSH access from GCS
```
G-Control.exe (10.5.6.50) → pxlabs_cli.exe relay <action>
  → Paramiko SSH → vind-admin@10.5.5.77:22  (direct, NOT via tunnel)
  → command executes on relay
```

### Commands GCS fires on relay
| GCS Action | SSH Command |
|---|---|
| relay wfb switch --mode standalone | `sudo /usr/local/sbin/wfb-rlyctl use-standalone` |
| relay wfb switch --mode cluster | `sudo /usr/local/sbin/wfb-rlyctl use-cluster` |
| relay wfb status | `wfb-rlyctl status` |
| relay wfb logs | `journalctl -u wifibroadcast@gs + wifibroadcast-cluster@gs` |
| relay wfb set-nics | `sudo wfb-rlyctl set-nics <iface>` |
| relay reboot | `sudo systemd-run --on-active=0 systemctl reboot` |
| relay shutdown | `sudo systemd-run --on-active=0 systemctl poweroff` |
| relay ssh-terminal | opens SSH terminal window on GCS PC |
| services refresh/start/stop (--target relay) | `systemctl is-active/enable/disable` etc. |

SSH user: `vind-admin` | Password: keyring / env `PXLABS_RELAY_PASSWORD`

> `wfb-rlyctl` sudoers: `/etc/sudoers.d/wfb-rlyctl` — passwordless sudo scoped to this script.
> GCS polls WFB mode on panel open and after every switch (4 s settle timer).
> Pull tab in G-Control shows: ◉ standalone (green) / ⬡ cluster (blue) / ⊙ unknown (dim).

### Critical dependency
`ssh-tunnel-to-companion.service` (autossh) must be running on relay for GCS to SSH to companion.
If relay is rebooted, this service must restart automatically — it is enabled and set to restart on failure.

## 15) Release History

| Tag | Commit | Date | Key Changes |
|---|---|---|---|
| `v1.0.0` | `2695911` | 2026-02-22 | Initial relay backup: system files, docs, sync infrastructure |
| `v1.0.1` | `6c46493` | 2026-03-15 | WFB-NG cluster/standalone mode; cluster service, SSH key, mediamtx config |
| `v1.0.2` | `ae857c9` | 2026-03-15 | Security: remove sudo password from docs; network docs, GCS details |
| `v1.0.3` | `01f4186` | 2026-07-10 | wfb-rlyctl backup, channel 157→161, sync script fix (rsync resilience + regex) |
| `v1.0.4` | `9ee8e03` | 2026-07-10 | Fix cluster [cluster] section (wiped 2026-02-22), correct ssh_key path, full WFB-NG config reference, GCS interface docs |

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
**2026-03-15 20:29**
- A	System_files/usr/local/sbin/wfb-rlyctl
**2026-03-15 21:55**
- M	System_files/etc/wifibroadcast.cfg
