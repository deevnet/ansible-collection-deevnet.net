"""Filter plugin for Omada controller API helpers."""

# The payload below is shaped for the controller's internal web API, used only by
# playbooks/migration/13-omada-ssids.yml. omada-wireless.yml builds its own body
# from the documented Open API schema instead (ADR-0009).
# omada-api: UNDOCUMENTED POST /{omadacId}/api/v2/sites/{siteId}/setting/wlans/{wlanId}/ssids tested-on 6.1.0.19


def omada_ssid_payload(vlan_entry, wifi_password, guest=False):
    """Build an Omada SSID creation payload from a VLAN definition.

    Args:
        vlan_entry: Dict with 'key' (vlan name) and 'value' (vlan config
            including wifi_ssid, vlan_id).
        wifi_password: The WPA2/WPA3 pre-shared key.
        guest: Whether this is a guest network (enables client isolation).

    Returns:
        Dict suitable for POST to the Omada SSID creation endpoint.
    """
    return {
        'name': vlan_entry['value']['wifi_ssid'],
        'band': 3,  # 2.4 + 5 GHz
        'type': 0,
        'guestNetEnable': guest,
        'security': 3,  # WPA2/WPA3
        'broadcast': True,
        'vlanSetting': {
            'mode': 1,
            'customConfig': {
                'vlanId': vlan_entry['value']['vlan_id'],
            },
        },
        'pskSetting': {
            'securityKey': wifi_password,
            'encryptionPsk': 3,
            'versionPsk': 2,
            'gikRekeyPskEnable': False,
        },
        'rateLimit': {'rateLimitId': ''},
        'ssidRateLimit': {'rateLimitId': ''},
        'rateAndBeaconCtrl': {
            'rate2gCtrlEnable': False,
            'rate5gCtrlEnable': False,
            'rate6gCtrlEnable': False,
            'beaconRate2g': 0,
            'beaconRate5g': 0,
            'beaconRate6g': 0,
        },
        'wlanScheduleEnable': False,
        'macFilterEnable': False,
        'enable11r': False,
        'pmfMode': 3,
        'wpaPsk': [2, 3],
        'deviceType': 1,
        'dhcpOption82': {'dhcpEnable': False},
        'greEnable': False,
        'prohibitWifiShare': False,
        'mloEnable': False,
    }


class FilterModule:
    def filters(self):
        return {
            'omada_ssid_payload': omada_ssid_payload,
        }
