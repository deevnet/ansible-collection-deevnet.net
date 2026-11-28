"""Unit tests for plugins/filter/dhcp_helpers.py.

Run from the collection root:  python3 -I tests/unit/plugins/filter/test_dhcp_helpers.py
"""

import copy
import importlib.util
import pathlib
import unittest

_PATH = pathlib.Path(__file__).resolve().parents[4] / 'plugins' / 'filter' / 'dhcp_helpers.py'
_spec = importlib.util.spec_from_file_location('dhcp_helpers', _PATH)
h = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(h)


def _opt(*values):
    return {v: {'value': v, 'selected': 1} for v in values}


# The shape get_subnet returns on the core router (2026-11-28), trimmed.
HAVE = {
    'subnet': '10.20.99.0/24',
    'description': 'management (VLAN 99)',
    'next_server': '10.20.99.97',
    'pools': '10.20.99.200 - 10.20.99.230',
    'match-client-id': '1',
    'interface': {'': {'value': 'None', 'selected': 1}},
    'option_data': {
        'domain_name': 'deevnet.net',
        'domain_name_servers': _opt('10.20.99.1'),
        'domain_search': _opt(''),
        'ntp_servers': _opt('10.20.99.1'),
        'routers': _opt('10.20.99.1'),
        'classless_static_route': '',
    },
    'option_data_autocollect': '1',
}

WANT = {
    'pools': '10.20.99.200 - 10.20.99.230',
    'description': 'management (VLAN 99)',
    'option_data': {
        'routers': '10.20.99.1',
        'domain_name_servers': '10.20.99.1',
        'domain_name': 'deevnet.net',
    },
}


class KeaSubnetDiff(unittest.TestCase):

    def test_matching_subnet_has_no_diff(self):
        self.assertEqual(h.kea_diff(WANT, HAVE), {})

    def test_pool_whitespace_is_not_drift(self):
        want = dict(WANT, pools='10.20.99.200-10.20.99.230')
        self.assertEqual(h.kea_diff(want, HAVE), {})

    def test_moved_pool_is_drift(self):
        want = dict(WANT, pools='10.20.99.150 - 10.20.99.230')
        self.assertEqual(h.kea_diff(want, HAVE), {'pools': '10.20.99.150 - 10.20.99.230'})

    def test_nested_option_data_diff_sends_only_that_field(self):
        want = copy.deepcopy(WANT)
        want['option_data']['domain_name_servers'] = '10.20.99.53'
        self.assertEqual(
            h.kea_diff(want, HAVE),
            {'option_data': {'domain_name_servers': '10.20.99.53'}})

    def test_next_server_left_out_of_want_is_never_compared(self):
        self.assertNotIn('next_server', h.kea_diff(WANT, HAVE))

    def test_next_server_declared_is_compared(self):
        want = dict(WANT, next_server='10.20.99.95')
        self.assertEqual(h.kea_diff(want, HAVE), {'next_server': '10.20.99.95'})

    def test_empty_next_server_on_router(self):
        have = dict(HAVE, next_server='')
        want = dict(WANT, next_server='10.20.99.95')
        self.assertEqual(h.kea_diff(want, have), {'next_server': '10.20.99.95'})

    def test_field_missing_from_router_is_drift(self):
        have = copy.deepcopy(HAVE)
        del have['description']
        self.assertEqual(h.kea_diff(WANT, have), {'description': 'management (VLAN 99)'})

    def test_option_list_with_two_values(self):
        have = copy.deepcopy(HAVE)
        have['option_data']['domain_name_servers'] = _opt('10.20.99.1', '10.20.99.2')
        want = copy.deepcopy(WANT)
        want['option_data']['domain_name_servers'] = '10.20.99.1, 10.20.99.2'
        self.assertEqual(h.kea_diff(want, have), {})


class KeaSubnetDriftReport(unittest.TestCase):

    def test_report_names_field_and_both_values(self):
        want = dict(WANT, next_server='10.20.99.95')
        self.assertEqual(
            h.kea_drift_report(want, HAVE),
            ["next_server: '10.20.99.97' -> '10.20.99.95'"])


class KeaSubnetChanged(unittest.TestCase):

    def test_only_sent_field_changed(self):
        after = dict(HAVE, next_server='10.20.99.95')
        self.assertEqual(h.kea_changed(HAVE, after, {'next_server': '10.20.99.95'}), [])

    def test_unsent_field_changed_is_reported(self):
        after = copy.deepcopy(HAVE)
        after['next_server'] = '10.20.99.95'
        after['option_data']['routers'] = {}
        self.assertEqual(
            h.kea_changed(HAVE, after, {'next_server': '10.20.99.95'}),
            ['option_data.routers'])

    def test_unsent_field_set_is_reported(self):
        after = copy.deepcopy(HAVE)
        after['option_data']['classless_static_route'] = '10.0.0.0/8 - 10.20.99.1'
        self.assertEqual(
            h.kea_changed(HAVE, after, {'pools': HAVE['pools']}),
            ['option_data.classless_static_route'])


class KeaReservation(unittest.TestCase):
    # get_reservation returns the subnet as an option list keyed by UUID.
    HAVE = {
        'subnet': {'': {'value': 'None', 'selected': 0},
                   'uuid-mgmt': {'value': '10.20.99.0/24', 'selected': 1},
                   'uuid-iot': {'value': '10.20.30.0/24', 'selected': 0}},
        'ip_address': '10.20.99.95',
        'hw_address': 'c8:ff:bf:06:5a:59',
        'hostname': 'dv00bld001p01',
        'description': 'Ansible managed - dv00bld001p01',
        'option_data': {'tftp_server_name': '', 'boot_file_name': '', 'domain_name': ''},
    }
    WANT = {
        'subnet': 'uuid-mgmt',
        'ip_address': '10.20.99.95',
        'hostname': 'dv00bld001p01',
        'description': 'Ansible managed - dv00bld001p01',
        'option_data': {'tftp_server_name': '', 'boot_file_name': ''},
    }

    def test_unchanged_reservation_has_no_drift(self):
        self.assertEqual(h.kea_drift_report(self.WANT, self.HAVE), [])

    def test_moved_subnet_is_drift(self):
        want = dict(self.WANT, subnet='uuid-iot')
        self.assertEqual(h.kea_drift_report(want, self.HAVE), ["subnet: 'uuid-mgmt' -> 'uuid-iot'"])

    def test_pxe_boot_added_is_drift(self):
        want = copy.deepcopy(self.WANT)
        want['option_data']['tftp_server_name'] = '10.20.99.97'
        self.assertEqual(h.kea_diff(want, self.HAVE), {'option_data': {'tftp_server_name': '10.20.99.97'}})


class DhcpSubnetForIp(unittest.TestCase):

    def test_finds_containing_subnet(self):
        m = {'10.20.10.0/24': 'a', '10.20.99.0/24': 'b'}
        self.assertEqual(h.dhcp_subnet_for_ip('10.20.99.95', m), 'b')

    def test_no_match(self):
        self.assertEqual(h.dhcp_subnet_for_ip('192.0.2.1', {'10.20.10.0/24': 'a'}), '')


if __name__ == '__main__':
    unittest.main()
