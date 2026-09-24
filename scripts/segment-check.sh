#!/bin/bash
#
# Segment Reachability Check
# Run from a laptop joined to one of the mobile site's SSIDs. Checks that the
# segment behind that SSID reaches what the zone policy says it may, and is
# refused everything it may not - from a real client, which is the only place
# the router's policy can be observed (Ansible reports what it wrote, not what
# a client gets).
#
# Usage: bash segment-check.sh <SSID>
#        bash segment-check.sh --list
#
# Read-only: it resolves names and opens TCP connections, nothing else.
# macOS first (BSD nc, scutil); Linux works where timeout(1) and dig exist.
#
# How a result is read:
#   REACH  passes if the connection opens OR is refused: either way the packet
#          got through the router to the host. Only a timeout fails it.
#   BLOCK  passes only on a timeout. The router drops what policy denies, so a
#          refusal means the packet reached the host - that is a LEAK.
#
# The profiles below are derived from the mobile inventory's
# group_vars/all/firewall.yml (zone policy, firewall_internet_zones,
# firewall_internet_private_zones) and vlans.yml (SSIDs, subnets). They are a
# second copy of that policy, written by hand so the script runs on a laptop
# with nothing installed: change them in the same PR as the policy.
#
# History: CHG-0022 (tenant dev network) and CHG-0023 (internet means
# internet) were verified with the tenant-dev profile of this script.
# CHG-0024 (logs :8427, Grafana :3000) and CHG-0025 (downloads :8443) added
# their tenant-dev checks.

set -u

# --- Hosts the profiles point at -------------------------------------------
# A BLOCK against a host that is switched off passes whatever the policy says -
# a dead host times out too - and a REACH against one fails. The IoT Pis are
# often off: their REACH failures from trusted mean "off" as often as "denied",
# and their BLOCK passes are marked if-on, meaning they only prove something
# while that Pi is running. The broker host (iot_backend) is always on and is
# the dependable check on the IoT side.
BUILDER=10.20.99.95        # dv00bld001p01, management
ROUTER_MGMT=10.20.99.1     # dv02cor002p01 on management
HYPERVISOR=10.20.99.21     # dv02hyp001p01, management
PRV=10.20.25.20            # dv02prv001v01, platform: API :8080, tfstate :9000
MSG=10.20.35.20            # dv02msg001v01, iot_backend: broker :8883
OBS=10.20.25.22            # dv02obs001v01, platform: logs :8427, Grafana :3000, downloads :8443
PIS="10.20.30.11 10.20.30.12 10.20.30.13 10.20.30.14"   # dv02rpi001p01-004p01, iot
WORKLOAD=10.20.130.10      # services.eds, tenant overlay
EDGE=192.168.8.1           # dv02edg001p01 admin, upstream private space

# --- Profiles ----------------------------------------------------------------
# One line per check:  kind  target  port  label
#   subnet   <prefix>                 lease must be in this /24 (prefix "10.20.45.")
#   resolve  <name>                   must resolve through the segment gateway
#   https    <name>  <port>           HTTPS answers, verified against the site CA
#   http     <name>  <port>           HTTP answers
#   tls      <name>  <port>           TLS handshake verified against the site CA
#   reach    <host>  <port>  <label>
#   block    <host>  <port>  <label>
#   internet                          https://example.com answers 200

profile() {
  case "$1" in
  DVNTM) cat <<EOF
subnet 10.20.10.
resolve api.mobile.deevnet.net
resolve mqtt.mobile.deevnet.net
internet
reach $BUILDER 22 Builder-ssh(management,lab-exception)
reach $ROUTER_MGMT 443 router-GUI(management)
reach $HYPERVISOR 8006 hypervisor-PVE(management)
https api.mobile.deevnet.net 8080
http tfstate.mobile.deevnet.net 9000
reach $PRV 22 prv-ssh(platform)
tls mqtt.mobile.deevnet.net 8883
reach $MSG 8883 broker(iot_backend)
$(for h in $PIS; do echo "reach $h 22 pi(iot,fails-if-off)"; done)
reach $WORKLOAD 22 tenant-workload(ADR-0018)
reach $EDGE 80 edge-router-admin(exempt,CHG-0023)
block 10.20.31.1 443 router-on-iot_vendor
block 10.20.40.1 443 router-on-guest
block 10.20.45.1 443 router-on-tenant_dev
EOF
  ;;
  DVNTM-TD) cat <<EOF
subnet 10.20.45.
resolve api.mobile.deevnet.net
resolve tfstate.mobile.deevnet.net
resolve mqtt.mobile.deevnet.net
resolve downloads.mobile.deevnet.net
https api.mobile.deevnet.net 8080
http tfstate.mobile.deevnet.net 9000
tls mqtt.mobile.deevnet.net 8883
tls dv02obs001v01.mobile.deevnet.net 8427
https dv02obs001v01.mobile.deevnet.net 3000
https downloads.mobile.deevnet.net 8443
internet
block $OBS 22 obs-ssh(platform)
block $BUILDER 22 Builder-ssh(management)
block $ROUTER_MGMT 443 router-GUI(management)
block $HYPERVISOR 8006 hypervisor-PVE(management)
block 10.20.45.1 443 router-GUI-on-own-gateway
block 10.20.45.1 22 router-ssh-on-own-gateway
block 10.20.10.1 443 router-on-trusted
block $PRV 22 prv-ssh(platform)
block $PRV 8200 prv-other-port(platform)
block $MSG 22 msg-ssh(iot_backend)
block $MSG 1883 broker-plaintext(iot_backend)
block $WORKLOAD 22 tenant-workload
$(for h in $PIS; do echo "block $h 22 pi(iot,if-on)"; done)
block $EDGE 80 edge-router-admin(CHG-0023)
EOF
  ;;
  DVNTM-IOT) cat <<EOF
subnet 10.20.30.
resolve mqtt.mobile.deevnet.net
tls mqtt.mobile.deevnet.net 8883
internet
block $BUILDER 22 Builder-ssh(management)
block $ROUTER_MGMT 443 router-GUI(management)
block 10.20.30.1 443 router-GUI-on-own-gateway
block $PRV 8080 deevnet-API(platform)
block $PRV 9000 tfstate(platform)
block $WORKLOAD 22 tenant-workload(ADR-0020)
block 10.20.10.1 443 router-on-trusted
block $EDGE 80 edge-router-admin(CHG-0023)
EOF
  ;;
  DVNTM-IOTV) cat <<EOF
subnet 10.20.31.
internet
block $BUILDER 22 Builder-ssh(management)
block $ROUTER_MGMT 443 router-GUI(management)
block 10.20.31.1 443 router-GUI-on-own-gateway
block $PRV 8080 deevnet-API(platform)
block $MSG 8883 broker(iot_backend)
block $WORKLOAD 22 tenant-workload
$(for h in $PIS; do echo "block $h 22 pi(iot,if-on)"; done)
block $EDGE 80 edge-router-admin(CHG-0023)
EOF
  ;;
  DVNTM-GUEST) cat <<EOF
subnet 10.20.40.
internet
block $BUILDER 22 Builder-ssh(management)
block $ROUTER_MGMT 443 router-GUI(management)
block 10.20.40.1 443 router-GUI-on-own-gateway
block 10.20.40.1 22 router-ssh-on-own-gateway
block $PRV 8080 deevnet-API(platform)
block $MSG 8883 broker(iot_backend)
block $WORKLOAD 22 tenant-workload
$(for h in $PIS; do echo "block $h 22 pi(iot,if-on)"; done)
block 10.20.10.1 443 router-on-trusted
block $EDGE 80 edge-router-admin(CHG-0023)
EOF
  ;;
  *) return 1 ;;
  esac
}
SSIDS="DVNTM DVNTM-TD DVNTM-IOT DVNTM-IOTV DVNTM-GUEST"

usage() {
  echo "usage: bash $0 <SSID>    (one of: $SSIDS)" >&2
  echo "       bash $0 --list    print each SSID's checks" >&2
  exit 2
}

[ $# -eq 1 ] || usage
if [ "$1" = "--list" ]; then
  for s in $SSIDS; do echo "== $s"; profile "$s" | sed 's/^/  /'; done
  exit 0
fi
SSID=$(echo "$1" | tr '[:lower:]' '[:upper:]')
CHECKS=$(profile "$SSID") || usage

# --- Site CA (mobile internal CA, valid to 2036-09-14) ------------------------
CA=$(mktemp); trap 'rm -f "$CA"' EXIT
cat > "$CA" <<'PEM'
-----BEGIN CERTIFICATE-----
MIIDOzCCAiOgAwIBAgIUNFURi+BYDXa773TCiFB57bjC7OkwDQYJKoZIhvcNAQEL
BQAwJTEjMCEGA1UEAxMaRGVldm5ldCBtb2JpbGUgaW50ZXJuYWwgQ0EwHhcNMjYw
OTE3MjM1NjA2WhcNMzYwOTE0MjM1NjM2WjAlMSMwIQYDVQQDExpEZWV2bmV0IG1v
YmlsZSBpbnRlcm5hbCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
AM7UYiY+Zar9LzJZubkQqVFulWBxXkxteJt6n6qQzQ4JBpJ+Fns12ZOazFQPJhcE
Lrjsod9f+xmo5VlObQewKCCd8EsK+DiXOI2ky44rfzoFRGJ95N/bNp+ohS/neBIi
oDix1feTVx0d6A+Oto/2vGJzqWbb0EAOwnFKowqdfUNS40cgSeVo3bm03uN9iOmk
Zmn/cjfI2ZEfcJ007ADxiJmX7bfXhOUbvrMKoShM3mmpOC8TVo4c8b5bsHwjOUJU
BIo6KHsOCBu1EePUXvz7vMC7//EWu1FMUp0UcLE0pxuLHMrUA80BVqqbmVJpB3AK
4bK6mAG9zGEeJtE+N2muk3ECAwEAAaNjMGEwDgYDVR0PAQH/BAQDAgEGMA8GA1Ud
EwEB/wQFMAMBAf8wHQYDVR0OBBYEFJKXklMLQkz8utmOfxlCD3cWlqnGMB8GA1Ud
IwQYMBaAFJKXklMLQkz8utmOfxlCD3cWlqnGMA0GCSqGSIb3DQEBCwUAA4IBAQCQ
D/V6muGHw5C8GFRUcIxK4VY/bhl5omj/IC1ma3a5iZMTWnyQKRHQT8EXDKWySjKK
603JD3EVRyvIWJKYa0tpdv0oBR+vUIpGJiC1CNHQfXyXtHHYWqE7vR0tuMFRZ0xn
b3EXKC3FuOSicwGsIZ4ezbqMxEHueniJ6Upw24PXvtLd0WI0JlQXu0+3OHaSkRQf
0bNw/Ie/GbiQ5cys2K60X27kl+X/HxthCPnB+2VhFoE4zRfLUMm23rlJOQN4t+8W
3Fp1LHrcQzpZdlilEJH7wBdqyQ/RDp4Tv/RSd0pfsbbqmjPoZOLx3GCWjCVY93GH
gmqLFDJRFNdwqOjx4/3N
-----END CERTIFICATE-----
PEM

P=0; F=0
ok()  { printf '  PASS  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  FAIL  %s\n' "$1"; F=$((F+1)); }

# tcp <host> <port>  ->  open | refused | timeout
tcp() {
  local o
  if [ "$(uname)" = Darwin ]; then
    o=$(nc -vz -G 3 -w 3 "$1" "$2" 2>&1)
    case "$o" in
      *succeeded*|*open*|*Connected*) echo open ;;
      *refused*|*"No route"*|*unreachable*) echo refused ;;
      *) echo timeout ;;
    esac
  else
    o=$(timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then echo open
    elif [ $rc -eq 124 ]; then echo timeout
    else case "$o" in *refused*|*"No route"*|*unreachable*) echo refused ;; *) echo timeout ;; esac
    fi
  fi
}

# --- Where are we ------------------------------------------------------------
if [ "$(uname)" = Darwin ]; then
  IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  IP=$(ipconfig getifaddr "$IF" 2>/dev/null)
else
  IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}')
fi
GW_PREFIX=$(echo "$CHECKS" | awk '$1=="subnet"{print $2}')
GW="${GW_PREFIX}1"

echo "Segment check: $SSID (from ${IP:-no address})"

while read -r kind a b c; do
  case "$kind" in
  subnet)
    echo "== Address and DNS"
    case "$IP" in
      "$a"*) ok "lease $IP" ;;
      *) bad "lease is '${IP:-none}', want ${a}x - are you on $SSID?"
         echo; echo "RESULT: stopped - not on $SSID"; exit 1 ;;
    esac ;;
  resolve)
    srv=$(dig +time=3 +tries=1 "$a" 2>/dev/null | awk '/^;; SERVER:/{split($3,s,"#"); print s[1]}')
    ans=$(dig +short +time=3 +tries=1 "$a" 2>/dev/null | tail -1)
    if [ -z "$ans" ]; then bad "$a does not resolve"
    elif [ "$srv" != "$GW" ] && [ "$srv" != "127.0.0.53" ]; then bad "$a -> $ans, but answered by $srv, not $GW (VPN / Private Relay / fixed DNS?)"
    else ok "$a -> $ans"; fi ;;
  https)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --cacert "$CA" "https://$a:$b/")
    case "$code" in [1-5][0-9][0-9]) ok "REACH https://$a:$b - HTTP $code (TLS verified)" ;;
      *) bad "https://$a:$b no HTTP response" ;; esac ;;
  http)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$a:$b/")
    case "$code" in [1-5][0-9][0-9]) ok "http://$a:$b answered HTTP $code" ;;
      *) bad "http://$a:$b no HTTP response" ;; esac ;;
  tls)
    if [ "$(tcp "$a" "$b")" = open ]; then
      v=$(echo | openssl s_client -connect "$a:$b" -servername "$a" -CAfile "$CA" 2>&1 | grep -m1 'Verify return code')
      case "$v" in *"0 (ok)"*) ok "$a:$b TLS verified" ;; *) bad "$a:$b reachable, TLS: $v" ;; esac
    else bad "$a:$b not reachable"; fi ;;
  internet)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://example.com/)
    [ "$code" = 200 ] && ok "internet (https://example.com 200)" || bad "internet: got '$code'" ;;
  reach)
    r=$(tcp "$a" "$b")
    [ "$r" = timeout ] && bad "REACH $c $a:$b timed out" || ok "REACH $c $a:$b ($r)" ;;
  block)
    r=$(tcp "$a" "$b")
    [ "$r" = timeout ] && ok "BLOCK $c $a:$b" || bad "BLOCK $c $a:$b is $r - LEAK" ;;
  esac
done <<EOF
$CHECKS
EOF

echo; echo "RESULT: $SSID - $P passed, $F failed"
[ "$F" -eq 0 ]
