#!/bin/sh
#
# OPNsense Core Router Diagnostic Collection
# Collects system, interface, routing, pf, gateway and log state into one file
# for offline examination. Read-only: it inspects, it never reconfigures.
#
# Usage: sh opnsense-diag.sh
#
# Writes /tmp/deevnet-router-diag-<timestamp>.txt and prints that path on stderr
# when it finishes. Hand the file over with:
#   scp root@<router>:/tmp/deevnet-router-diag-*.txt .
#
# Break-glass tool: run it from the console or an SSH session when the router
# is misbehaving and Ansible cannot reach it. Nothing here depends on configd,
# the API or the web UI being healthy.
#
# NOTE: the output contains the full pf ruleset, interface addresses, ARP
# tables and log excerpts - internal topology. Review before sharing, and do
# not commit the output back into this repo.
#

OUT="/tmp/deevnet-router-diag-$(date +%Y%m%d-%H%M%S).txt"

# Keep the real stderr on fd 3 so the closing message reaches the operator's
# terminal instead of being swallowed by the redirect below.
exec 3>&2
exec > "$OUT" 2>&1

section() {
    echo
    echo "======================================================================"
    echo "  $1"
    echo "======================================================================"
    echo
}

# Network probes hang for a long time when DNS or the default route is the
# thing that is broken - which is the usual reason to be running this at all.
# Cap them when timeout(1) is available, run bare when it is not.
capped() {
    limit="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$limit" "$@"
    else
        "$@"
    fi
}

echo "DEEVNET OPNsense Diagnostic Collection"
echo "Collected: $(date)"
echo "Hostname:  $(hostname)"
echo "Output:    $OUT"

section "SYSTEM"
uname -a
uptime
date

section "OPNSENSE VERSION"
opnsense-version -v 2>&1 || echo "opnsense-version not available"

section "CONFIG HISTORY"
# Recent config revisions: the fastest way to see whether a change was applied
# to this router just before it started misbehaving.
echo "---- /conf/backup (newest 20) ----"
ls -lt /conf/backup 2>&1 | head -20
echo
echo "---- current config.xml ----"
ls -la /conf/config.xml 2>&1
grep -m1 -A4 '<revision>' /conf/config.xml 2>&1 || echo "no revision block found"

section "LAST BOOTS / REBOOTS"
last -x 2>&1 | head -50

section "INTERFACES"
ifconfig -a

section "ROUTING TABLE"
netstat -rn

section "ARP / NEIGHBORS"
arp -an

section "PF STATUS"
pfctl -si

section "PF INTERFACES"
pfctl -s Interfaces

section "PF RULES"
pfctl -sr

section "PF NAT RULES"
pfctl -sn

section "PF STATES - SUMMARY"
echo "State count:"
pfctl -ss | wc -l
echo
pfctl -s memory

section "PF STATES - SAMPLE"
pfctl -ss | head -300

section "GATEWAYS / ROUTING PROCESSES"
ps auxww | grep -E 'dpinger|dhclient|dhcp6c|radvd|unbound' | grep -v grep

section "LISTENING SOCKETS"
sockstat -46l

section "NETWORK STATISTICS"
netstat -s

section "INTERFACE STATISTICS"
netstat -i

section "CURRENT DMESG"
dmesg

section "SYSTEM LOG - LAST 500 LINES"
if [ -f /var/log/system/latest.log ]; then
    tail -500 /var/log/system/latest.log
else
    echo "/var/log/system/latest.log not found"
fi

section "GATEWAY LOG - LAST 300 LINES"
if [ -f /var/log/gateways/latest.log ]; then
    tail -300 /var/log/gateways/latest.log
else
    echo "/var/log/gateways/latest.log not found"
fi

section "FILTER LOG - LAST 300 LINES"
if [ -f /var/log/filter/latest.log ]; then
    tail -300 /var/log/filter/latest.log
else
    echo "/var/log/filter/latest.log not found"
fi

section "CRASH DIRECTORY"
ls -lah /var/crash 2>&1

section "FILESYSTEM"
df -h

section "MEMORY"
sysctl hw.physmem
sysctl hw.realmem 2>/dev/null
vmstat -s

section "TEMPERATURE / HARDWARE"
sysctl -a 2>/dev/null | grep -Ei \
'temperature|thermal|dev.cpu.*temp|hw.acpi.thermal' || true

section "PING - DEFAULT GATEWAY"
GW=$(netstat -rn | awk '$1 == "default" { print $2; exit }')
if [ -n "$GW" ]; then
    echo "default gateway: $GW"
    capped 15 ping -c 4 -W 2000 "$GW"
else
    echo "no default route present"
fi

section "PING - PUBLIC IP"
capped 15 ping -c 4 -W 2000 1.1.1.1

section "DNS TEST"
capped 15 drill google.com 2>&1 || capped 15 host google.com 2>&1 || true

section "IMPORTANT ERROR SEARCH"

for logfile in \
    /var/log/system/latest.log \
    /var/log/gateways/latest.log
do
    if [ -f "$logfile" ]; then
        echo
        echo "---- $logfile ----"
        grep -Ei \
        'panic|fatal|watchdog|lockup|hung|timeout|reset|thermal|temperature|oom|out of memory|memory error|hardware error|I/O error|nvme|ata|link.*down|link.*up|carrier|fault' \
        "$logfile" | tail -300
    fi
done

section "END"
echo "Diagnostic collection completed: $(date)"

echo "Wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines, $(du -h "$OUT" | awk '{print $1}'))" >&3
