"""Filter plugin for DHCP subnet UUID lookups."""

import ipaddress


def dhcp_subnet_for_ip(ip_address, subnet_by_cidr):
    """Find the subnet UUID for a given IP address.

    Args:
        ip_address: IP address string (e.g., '10.20.10.50').
        subnet_by_cidr: Dict mapping subnet CIDR to UUID
            (e.g., {'10.20.10.0/24': 'uuid-here'}).

    Returns:
        The subnet UUID string, or empty string if no match.
    """
    try:
        ip = ipaddress.ip_address(ip_address)
    except (ValueError, TypeError):
        return ''

    for cidr, uuid in subnet_by_cidr.items():
        try:
            network = ipaddress.ip_network(cidr, strict=False)
            if ip in network:
                return uuid
        except (ValueError, TypeError):
            continue
    return ''


class FilterModule:
    def filters(self):
        return {
            'dhcp_subnet_for_ip': dhcp_subnet_for_ip,
        }
