"""Filter plugin for Kea DHCP: subnet UUID lookups, and comparing a record's
(subnet or reservation) declared settings with what the router holds."""

import ipaddress
import re


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


# Comparing a Kea record (a subnet4 or a reservation)
# ------------------------------------------------------------------------------
# get_subnet does not hand back what set_subnet was sent. A multi-value field
# such as option_data.routers comes back as OPNsense's option list,
# {'10.20.10.1': {'value': '10.20.10.1', 'selected': 1}}, where it was sent as
# '10.20.10.1'; a single-choice field comes back the same way; and a pool comes
# back as '10.20.10.100 - 10.20.10.200' whether it was sent with spaces or not.
# Both sides are brought to one string form before they are compared.

def _is_option_list(value):
    return (
        isinstance(value, dict)
        and len(value) > 0
        and all(isinstance(v, dict) and 'selected' in v for v in value.values())
    )


def _norm(value):
    if value is None:
        return ''
    if _is_option_list(value):
        value = [k for k, v in value.items() if str(v.get('selected')) == '1' and k != '']
    if isinstance(value, (list, tuple)):
        value = ','.join(str(v) for v in value if str(v) != '')
    return re.sub(r'\s*([,-])\s*', r'\1', str(value).strip())


def _flatten(subnet, prefix=''):
    """{'option_data': {'routers': x}} -> {'option_data.routers': normalised x}"""
    out = {}
    for key, value in (subnet or {}).items():
        path = prefix + str(key)
        if isinstance(value, dict) and not _is_option_list(value):
            out.update(_flatten(value, path + '.'))
        else:
            out[path] = _norm(value)
    return out


def _leaves(subnet, prefix=''):
    """Like _flatten, but keeps each value as given."""
    out = {}
    for key, value in (subnet or {}).items():
        path = prefix + str(key)
        if isinstance(value, dict) and not _is_option_list(value):
            out.update(_leaves(value, path + '.'))
        else:
            out[path] = value
    return out


def kea_diff(want, have):
    """The part of `want` the router does not already hold.

    Args:
        want: The declared subnet4 fields, nested as set_subnet takes them
            (e.g. {'pools': 'a - b', 'option_data': {'routers': 'x'}}).
            A field left out of `want` is never compared.
        have: The subnet4 dict get_subnet returned.

    Returns:
        A dict nested like `want`, holding only the fields whose value
        differs, each with its declared value: the body to send. Empty when
        the subnet already matches.
    """
    have_flat = _flatten(have)
    out = {}
    for path, value in _leaves(want).items():
        if _norm(value) == have_flat.get(path, ''):
            continue
        node = out
        parts = path.split('.')
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    return out


def kea_drift_report(want, have):
    """One line per field that differs: "field: 'held' -> 'declared'"."""
    have_flat = _flatten(have)
    return [
        "%s: '%s' -> '%s'" % (path, have_flat.get(path, ''), _norm(value))
        for path, value in _leaves(want).items()
        if _norm(value) != have_flat.get(path, '')
    ]


def kea_changed(before, after, sent):
    """Fields that changed between two reads of a subnet but were not sent.

    Args:
        before: subnet4 as read before set_subnet.
        after: subnet4 as read after it.
        sent: The body set_subnet was sent; its fields are expected to change.

    Returns:
        A sorted list of dotted field names. Empty when set_subnet changed
        only what it was sent.
    """
    b, a = _flatten(before), _flatten(after)
    expected = set(_flatten(sent))
    return sorted(p for p in set(b) | set(a) if p not in expected and b.get(p, '') != a.get(p, ''))


class FilterModule:
    def filters(self):
        return {
            'dhcp_subnet_for_ip': dhcp_subnet_for_ip,
            'kea_diff': kea_diff,
            'kea_drift_report': kea_drift_report,
            'kea_changed': kea_changed,
        }
