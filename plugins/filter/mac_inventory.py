"""Filter plugin to cross-reference switch MAC address tables with Ansible inventory."""

import re

MAC_RE = re.compile(r'^[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}$')
# TP-Link port names: Gi1/0/1, Te1/0/1, etc.
PORT_RE = re.compile(r'^(?:Gi|Te|Fa)\d+/\d+/\d+$', re.IGNORECASE)


def mac_table_inventory(mac_stdout_lines, hostvars, groups):
    """Parse switch MAC table output and map each MAC to its inventory host.

    Args:
        mac_stdout_lines: List of lines from ``show mac address-table``.
        hostvars: The Ansible ``hostvars`` dict (all hosts).
        groups: The Ansible ``groups`` dict.

    Returns:
        dict with ``entries`` (list of dicts) and ``unknown`` (list of dicts).
    """
    # Build MAC -> "hostname (iface)" lookup from inventory
    lookup = {}
    for host in groups.get('all', []):
        hv = hostvars.get(host, {})
        infra = hv.get('infrastructure') or {}
        interfaces = infra.get('interfaces') or {}
        for iface_name, iface_data in interfaces.items():
            mac = (iface_data.get('mac') or '').strip()
            if mac and mac.upper() != 'UNKNOWN':
                lookup[mac.lower()] = '{} ({})'.format(host, iface_name)

    # Parse MAC table lines — detect columns by pattern rather than position,
    # since TP-Link column order varies by firmware.
    entries = []
    unknown = []
    for line in mac_stdout_lines:
        cols = line.split()
        if len(cols) < 3:
            continue

        mac = None
        vlan = None
        port = None
        for col in cols:
            if MAC_RE.match(col):
                mac = col.lower()
            elif PORT_RE.match(col):
                port = col

        if mac is None:
            continue

        # VLAN ID is the first purely numeric column in the line
        for col in cols:
            if col.isdigit():
                vlan = col
                break

        inv = lookup.get(mac, 'UNKNOWN')
        entry = {
            'mac': mac,
            'port': port or '—',
            'vlan': vlan or '—',
            'inventory': inv,
        }
        entries.append(entry)
        if inv == 'UNKNOWN':
            unknown.append(entry)

    return {'entries': entries, 'unknown': unknown}


def format_mac_table(mac_report):
    """Format the MAC report as an aligned text table.

    Args:
        mac_report: Dict returned by ``mac_table_inventory``.

    Returns:
        Multi-line string with a formatted table.
    """
    lines = [
        'Port            VLAN  MAC Address         Inventory Host',
        '--------------- ----- ------------------- ----------------------------',
    ]
    for e in mac_report.get('entries', []):
        lines.append('{:<15s} {:<5s} {:<19s} {}'.format(
            e['port'], e['vlan'], e['mac'], e['inventory']))
    return '\n'.join(lines)


class FilterModule:
    def filters(self):
        return {
            'mac_table_inventory': mac_table_inventory,
            'format_mac_table': format_mac_table,
        }
