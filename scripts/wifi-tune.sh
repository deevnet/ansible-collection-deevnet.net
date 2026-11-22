#!/usr/bin/env bash
# Adjust / measure loop for the AP's radios (playbooks/omada-radio-tune.yml).
#
# Run it on a Mac joined to the SSID under test, from the spot being tuned for,
# and do not move until it finishes. For each trial it:
#   1. sets the radios (skipped for a trial with no settings - the baseline)
#   2. waits for the Mac to reassociate
#   3. measures from the Mac (idle ping, then networkQuality) and reads the
#      AP's view of the Mac and its radio counters
#   4. appends one row to a CSV
# At the end - or on Ctrl-C - it puts back the radio settings it found.
#
# A trials file has one trial per line:  label|<extra-vars JSON>
#   baseline|{}
#   2g-ch6|{"radio_2g": {"channel": "6", "channelWidth": "2"}}
# A trial's settings stay in place for the next trial unless it sets them again.
#
# Needs the inventory vault decrypted (cd ansible-inventory-deevnet && make unvault).
#
# Usage:
#   scripts/wifi-tune.sh [-r repeats] [-k] trials.txt
#     -r  measurements per trial (default 2)
#     -k  keep the last trial's settings instead of restoring

set -euo pipefail

REPEATS=2
KEEP=false
while getopts "r:k" opt; do
  case $opt in
    r) REPEATS=$OPTARG ;;
    k) KEEP=true ;;
    *) sed -n '2,25p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
TRIALS=${1:?"usage: $0 [-r repeats] [-k] trials.txt"}

cd "$(dirname "$0")/.."
export ANSIBLE_COLLECTIONS_PATH=./.ansible/collections:~/.ansible/collections

IFACE=en0
MAC=$(ifconfig "$IFACE" | awk '/ether/{print $2}')
RUN=wifi-tune-$(date +%Y%m%d-%H%M%S)
OUT=scripts/$RUN
mkdir -p "$OUT"
CSV=$OUT/results.csv

play() {  # play <report.json> [extra-vars JSON]
  ansible-playbook playbooks/omada-radio-tune.yml \
    -e radio_client_mac="$MAC" -e radio_report="$PWD/$1" ${2:+-e "$2"} \
    > "$1.log" 2>&1 || { echo "playbook failed, see $1.log" >&2; return 1; }
}

wifi() {  # the Mac's own view of its link: channel, rssi, noise, tx rate
  system_profiler SPAirPortDataType 2>/dev/null | awk '
    /Current Network Information/ {on=1}
    /Other Local Wi-Fi Networks/  {on=0}
    on && /Channel:/        {ch=$2; band=$3; gsub(/[(,]/,"",band)}
    on && /Signal \/ Noise/ {sig=$4; noise=$7}
    on && /Transmit Rate/   {rate=$3}
    END {printf "%s,%s,%s,%s,%s", ch, band, sig, noise, rate}'
}

wait_for_link() {  # up to 90 s for an address and a route out
  for _ in $(seq 1 30); do
    ipconfig getifaddr "$IFACE" >/dev/null 2>&1 && ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && return 0
    sleep 3
  done
  echo "no link after 90 s" >&2; return 1
}

measure() {  # down_mbps,up_mbps,down_rpm,up_rpm,idle ping avg,jitter,loss
  # Ping first, on an idle link: straight after the upload phase the queues
  # are still full and the ping measures them instead.
  local nq ping
  ping=$(ping -c 30 -i 0.2 1.1.1.1 2>/dev/null | tail -2)
  nq=$(networkQuality -s -c 2>/dev/null || echo '{}')
  python3 - "$nq" "$ping" <<'EOF'
import json, re, sys
nq = json.loads(sys.argv[1] or "{}")
mbps = lambda k: round(nq.get(k, 0) / 1e6, 1)
loss = re.search(r"([\d.]+)% packet loss", sys.argv[2])
rtt = re.search(r"= [\d.]+/([\d.]+)/[\d.]+/([\d.]+)", sys.argv[2])
print(",".join(map(str, [mbps("dl_throughput"), mbps("ul_throughput"),
    round(nq.get("dl_responsiveness", 0)), round(nq.get("ul_responsiveness", 0)), rtt and rtt.group(1) or "", rtt and rtt.group(2) or "",
    loss and loss.group(1) or "100"])))
EOF
}

ap_row() {  # ap_row <first.json> <last.json>: the AP's view across the trial
  # The controller refreshes AP counters only every few minutes, so retry % is
  # taken over the whole trial and left blank when the counters did not move.
  python3 - "$1" "$2" <<'EOF'
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
c = b["client"]; band = "5g" if c.get("radioId") == 1 else "2g"
d = lambda k: b["traffic"][band].get(k, 0) - a["traffic"][band].get(k, 0)
retry = round(100 * d("txRetryPkts") / d("txPkts"), 1) if d("txPkts") > 0 else ""
live, cfg = b["live"][band], b["config"][band]
print(",".join(map(str, [band, live.get("actualChannel", "").split()[0], live.get("bandWidth", ""),
    cfg.get("txPowerLevel", ""), live.get("txPower", ""), c.get("rssi", ""), c.get("snr", ""),
    c.get("txRate", ""), c.get("rxRate", ""), live.get("busyUtil", ""), live.get("interUtil", ""), retry])))
EOF
}

# --- The settings to put back -------------------------------------------------

echo "run $RUN, client $MAC, $REPEATS measurement(s) per trial"
play "$OUT/original.json"
ORIGINAL=$(python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))["config"]
print(json.dumps({"radio_apply": True, "radio_2g": c["2g"], "radio_5g": c["5g"]}))' "$OUT/original.json")
echo "$ORIGINAL" > "$OUT/original-vars.json"

restore() {
  $KEEP && { echo "keeping the last trial's settings; original is in $OUT/original-vars.json"; return; }
  echo "restoring the original radio settings"
  play "$OUT/restored.json" "$ORIGINAL" && echo "restored"
}
trap restore EXIT
trap 'exit 130' INT TERM

echo "trial,rep,mac_channel,mac_band,mac_rssi,mac_noise,mac_rate,band,ap_channel,width,power_level,power_dbm,ap_rssi,ap_snr,ap_tx_rate,ap_rx_rate,busy_util,inter_util,ap_tx_retry_pct,down_mbps,up_mbps,down_rpm,up_rpm,idle_ping_ms,idle_jitter_ms,idle_loss_pct" > "$CSV"

# --- Trials -------------------------------------------------------------------

while IFS='|' read -r label vars; do
  [[ -z "$label" || "$label" == \#* ]] && continue
  echo "== $label"
  if [[ "$vars" != "{}" && -n "$vars" ]]; then
    apply=$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]); v["radio_apply"]=True; print(json.dumps(v))' "$vars")
    play "$OUT/$label-set.json" "$apply"
  fi
  wait_for_link
  sleep 10  # let rate control settle after reassociation
  play "$OUT/$label-start.json"
  for rep in $(seq 1 "$REPEATS"); do
    mac=$(wifi); m=$(measure)
    play "$OUT/$label-$rep.json"
    row="$label,$rep,$mac,$(ap_row "$OUT/$label-start.json" "$OUT/$label-$rep.json"),$m"
    echo "$row" >> "$CSV"
    echo "   $row"
  done
done < "$TRIALS"

echo
column -s, -t < "$CSV"
echo
echo "results: $CSV"
