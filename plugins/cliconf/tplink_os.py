"""Cliconf plugin for TP-Link Omada managed switches (SG series).

Minimal cliconf that sends commands and returns output.  No ``show
privilege`` or other IOS-specific operations.
"""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

import json

from ansible.plugins.cliconf import CliconfBase


class Cliconf(CliconfBase):

    def get_device_info(self):
        device_info = {"network_os": "deevnet.net.tplink_os"}
        return device_info

    def get_config(self, source="running", flags=None, format=None):
        if source not in ("running", "startup"):
            raise ValueError(
                "fetching configuration from %s is not supported" % source
            )
        cmd = "show running-config" if source == "running" else "show startup-config"
        return self.send_command(cmd)

    def edit_config(self, candidate=None, commit=True, replace=None, comment=None):
        responses = []
        for cmd in candidate:
            if cmd.strip():
                responses.append(self.send_command(cmd))
        return responses

    def get(self, command, prompt=None, answer=None, sendonly=False, newline=True, check_all=False):
        return self.send_command(
            command=command,
            prompt=prompt,
            answer=answer,
            sendonly=sendonly,
            newline=newline,
            check_all=check_all,
        )

    def get_device_operations(self):
        return {
            "supports_diff_match": True,
            "supports_diff_ignore_lines": False,
            "supports_config_replace": False,
            "supports_admin_nonce": False,
            "supports_commit": False,
            "supports_rollback": False,
            "supports_defaults": False,
            "supports_onbox_diff": False,
            "supports_commit_comment": False,
            "supports_multiline_delimiter": False,
            "supports_diff_replace": False,
            "supports_generate_diff": False,
        }

    def get_option_values(self):
        return {
            "format": ["text"],
            "diff_match": ["line", "none"],
            "diff_replace": ["line"],
            "output": [],
        }

    def get_capabilities(self):
        result = {
            "rpc": ["get", "get_config", "edit_config"],
            "device_info": self.get_device_info(),
            "device_operations": self.get_device_operations(),
            "network_api": "cliconf",
        }
        return json.dumps(result)
