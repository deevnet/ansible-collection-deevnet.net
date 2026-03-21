"""Filter plugin for OPNsense interface configuration checks."""


def vlans_needing_ip(deevnet_vlans, vlan_devices_by_tag, device_to_interface):
    """Identify VLAN interfaces that are missing IP configuration.

    Args:
        deevnet_vlans: Dict of VLAN definitions from inventory.
        vlan_devices_by_tag: Dict mapping VLAN tag (str) to device name.
        device_to_interface: Dict mapping device name to interface info
            (identifier, ipv4, enabled).

    Returns:
        List of dicts with name, vlan_id, gateway, identifier, device
        for each VLAN that needs IP configuration.
    """
    result = []
    for name, vlan in deevnet_vlans.items():
        gateway = vlan.get('gateway')
        if not gateway:
            continue
        vlan_id = str(vlan.get('vlan_id', ''))
        device = vlan_devices_by_tag.get(vlan_id, '')
        iface = device_to_interface.get(device, {})
        identifier = iface.get('identifier', '?')
        current_ip = iface.get('ipv4', '')
        if not current_ip or gateway not in current_ip:
            result.append({
                'name': name,
                'vlan_id': vlan.get('vlan_id'),
                'gateway': gateway,
                'identifier': identifier,
                'device': device,
            })
    return result


def format_vlans_needing_ip(vlans_list):
    """Format the list of VLANs needing IP config for display.

    Args:
        vlans_list: List returned by vlans_needing_ip.

    Returns:
        Multi-line string with instructions.
    """
    lines = ['The following VLAN interfaces need IP configuration via OPNsense GUI:', '']
    for v in vlans_list:
        lines.append('  - {identifier} ({device}): {gateway}/24 — {name} (VLAN {vlan_id})'.format(**v))
    lines.append('')
    lines.append('For each interface: Interfaces → [name] → IPv4: Static, address/24, enable → Save')
    lines.append('After all interfaces are configured, click "Apply changes".')
    return '\n'.join(lines)


class FilterModule:
    def filters(self):
        return {
            'vlans_needing_ip': vlans_needing_ip,
            'format_vlans_needing_ip': format_vlans_needing_ip,
        }
