# CPE610 cluster node — snapshot

Captured 2026-09-26, the day the 2-node WFB cluster was first verified on RF.

**Why this directory exists.** The CPE610 is a separate device, so
`System_files_list.txt` / `system_files_sync.sh` cannot back it up — that script rsyncs
from the *relay's* `/`. Everything here was pulled off the node by hand and is the only
copy outside the device itself. Nothing in this directory is deployed by any script;
restoring is manual.

## The device

- **Hardware:** TP-Link CPE610 v2 (ath79, single 5 GHz radio, mips_24kc)
- **Firmware:** OpenWrt 24.10.4, r28959-29397011cc, kernel 6.6.110
- **Role:** receive node in `wifibroadcast-cluster@gs`, monitor iface `phy0-mon0` on ch161
- **Address:** 10.5.7.102/24 on `br-lan` (eth0), reached only from the relay's eth0 (10.5.7.100)
- **Login:** `ssh -i ~/.ssh/wfb_cluster_ed25519 root@10.5.7.102`, **from the relay** — the
  companion has no route to 10.5.7.0/24
- **wfb-ng:** `25.01-r1`, installed 2025-10-19

## Two things that surprise people

**It has no internet, and that is structural.** `radio0` is `disabled '1'` at the device
level, so the leftover `sta` config for the house SSID never comes up and `phy0-sta0` does
not exist — hence no default route, and `opkg` cannot fetch anything. There is also no
package feed configured. More importantly the CPE610 has **one radio**: it cannot be a
station on the house network and a monitor interface on ch161 at the same time. So any
package has to arrive as an `.ipk` carried in over Ethernet via the relay, not downloaded.

**It is effectively an RX-only node, and no version bump changes that.** The relay's
RTL8812EU reports `rssi_avg` around **+14..+16** with real SNR; this node's ath9k reports
true dBm, around **−23..−21**, and supplies no noise figure so SNR reads 0. The server's TX
selector compares those numbers against `tx_sel_rssi_delta = 3`, so the relay's own card
always wins and transmits — confirmed in the API: `tunnel tx` goes out on antenna
`0x7F000001…`. That is a chipset/driver difference, not a fault. One of the original
commented-out config variants had this node as `'wifi_txpower': 'off'`, i.e. rx-only, which
is what the hardware gives you anyway.

Its receive contribution is real and measured: 220 packets against the local card's 233 in
the same window, correct freq/mcs/bw, `dec_err: [0, 0]`.

## Version skew (open, not a defect)

Node `25.01-r1` vs relay and drone/companion both `25.4.27.73439`. In cluster mode the node
is a dumb pipe — `wfb_rx -f` forwards captured frames to the server, `wfb_tx -I` injects
frames the server built. No key, no FEC, no session state on the node. So the only contract
that must hold across versions is the framing of those UDP datagrams, and it holds: the
server parses this node's metadata correctly. Closing the skew means building wfb-ng
25.4.27 for `mips_24kc` against the OpenWrt 24.10 ath79 SDK on an x86 host with internet,
then carrying the `.ipk` in. Worth doing as hygiene; nothing is broken without it.

## Restore after a reflash

1. Flash `~/Openwrt_WFB_NG/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin`
   (on the relay).
2. Set `br-lan` to 10.5.7.102/24 per `etc/config/network`, and authorise the relay's
   `wfb_cluster_ed25519` public key for root.
3. Install wfb-ng + wfb-ng-tun. The relay holds only `24.9.7-r2` `.ipk`s, which are **older**
   than what was running; prefer building 25.4.27 (see above) over installing those.
4. Restore `usr/sbin/wfb-mon0.sh` (mode 755). It creates `phy0-mon0` and sets ch161. Note
   WFB-NG's generated init runs it **first** and then re-applies `iw reg set BO` and
   `set channel 161 HT20` from `[cluster]`, so the generated script has the last word on both
   regdomain and channel.
5. On the relay, `sudo wfb-rlyctl use-cluster` re-initialises the node over SSH automatically.

## Redactions and one security note

`etc/config/wireless` had a live PSK for the house SSID; the `option key` value is
**redacted** here. Ask the operator if it is ever needed — it is not required for cluster
operation, since that radio is disabled.

`etc/config/dropbear` has `PasswordAuth` and `RootPasswordAuth` both `on`. Key-based root
login already works from the relay, so both could be turned off. Left as found.
