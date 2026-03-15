"""Terminal plugin for TP-Link Omada managed switches (SG series).

TP-Link uses a Cisco-style CLI but differs in key ways:
  - ``terminal length 0`` requires enable mode
  - ``show privilege`` is not supported
  - Enable mode has no password prompt by default

This plugin handles those quirks so ``network_cli`` works cleanly.
"""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

import re

from ansible.errors import AnsibleConnectionFailure
from ansible.plugins.terminal import TerminalBase


class TerminalModule(TerminalBase):
    terminal_stdout_re = [
        re.compile(rb"[\r\n]?[\w\-\.]+[>|#]\s*$"),
    ]

    terminal_stderr_re = [
        re.compile(rb"Error:.*$", re.M),
    ]

    terminal_initial_prompt = None
    terminal_initial_answer = None

    def on_open_shell(self):
        # TP-Link requires enable mode before terminal commands work.
        # on_open_shell runs before on_become, so we just skip terminal
        # setup here — on_become will handle enable, then we set length.
        pass

    def on_become(self, passwd=None):
        prompt = self._get_prompt()
        if prompt is None:
            return

        if prompt.strip().endswith(b"#"):
            # Already in enable mode
            self._set_terminal_params()
            return

        cmd = b"enable"
        try:
            self._exec_cli_command(cmd)
        except AnsibleConnectionFailure:
            raise AnsibleConnectionFailure(
                "failed to elevate privilege to enable mode"
            )

        prompt = self._get_prompt()
        if prompt is None or not prompt.strip().endswith(b"#"):
            raise AnsibleConnectionFailure(
                "failed to elevate privilege to enable mode"
            )

        self._set_terminal_params()

    def _set_terminal_params(self):
        try:
            self._exec_cli_command(b"terminal length 0")
        except AnsibleConnectionFailure:
            pass
        try:
            self._exec_cli_command(b"terminal width 512")
        except AnsibleConnectionFailure:
            pass

    def on_unbecome(self):
        prompt = self._get_prompt()
        if prompt is None:
            return

        if prompt.strip().endswith(b">"):
            return

        self._exec_cli_command(b"disable")
