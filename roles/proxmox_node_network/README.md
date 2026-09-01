# proxmox_node_network

Configures a Proxmox VE node's bridge and VLAN sub-interfaces through the PVE
API, so a hypervisor's substrate attachment is inventory-driven like every
other network device in this collection.

Node interfaces are substrate, so they belong to Ansible. Terraform owns only
what lives inside the SDN fabric (ADR-0001).

Everything except the management routing unit goes through the API - no SSH,
no editing `/etc/network/interfaces` by hand.

## Variables

Supplied per hypervisor in `host_vars/<hv>/vars.yml`; see `hv02` for a worked
example.

| Variable | Purpose |
|---|---|
| `proxmox_node` | PVE node name, e.g. `pve2` |
| `proxmox_token_id` / `proxmox_token_secret` | API token carrying `Sys.Modify` |
| `proxmox_node_network.bridge` | Management bridge; made VLAN-aware |
| `proxmox_node_network.mgmt` | Management interface, CIDR, and whether it keeps a gateway |
| `proxmox_node_network.vlans` | VLAN sub-interfaces to create |
| `proxmox_mgmt_routing` | Source-based routing for the management address |

## Tags

Run in this order. The tags exist so the risky step is separable from the safe
ones, not as a convenience.

| Tag | What it does | Risk |
|---|---|---|
| `packages` | Installs `frr` and `dnsmasq` — the daemons that realize the SDN config (**needs SSH**) | None; without them the fabric exists in the API and does nothing |
| `interfaces` | Bridge becomes VLAN-aware; VLAN sub-interfaces created | Additive - nothing loses connectivity |
| `mgmt-routing` | Installs the source-based routing unit (**needs SSH**) | None on its own |
| `default-route` | Moves the default route off management onto transit | **Can cost access** - refuses to run unless `mgmt-routing` is active |

```bash
ansible-playbook playbooks/proxmox-node-network.yml --tags packages
ansible-playbook playbooks/proxmox-node-network.yml --tags interfaces
ansible-playbook playbooks/proxmox-node-network.yml --tags mgmt-routing
ansible-playbook playbooks/proxmox-node-network.yml --tags default-route
```

## Why the routing unit exists

The node's default route lives on the tenant transit segment so the data plane
never rides the management network. On its own that breaks management access
from other VLANs: a request arrives on the management interface and is answered
out transit, and the perimeter drops the asymmetric return.

The unit keys on the **source** address rather than the destination. Replies
from the management address go back out the management interface, while
forwarded tenant traffic - SNATed to the transit address, not this one - still
takes the default route out transit. A destination-based static route for the
site supernet would instead have pushed tenant-to-platform traffic back onto
the management VLAN.

It is a systemd unit rather than PVE network config because the PVE network API
models interfaces only, with no field for post-up hooks or routing tables, and
a second bridge stanza in `/etc/network/interfaces.d/` would collide with the
one the API owns.

## Why the daemons matter

The SDN objects are cluster configuration; `frr` and `dnsmasq` are what turn
them into a working network on the node. This is a confusing failure mode when
they are missing, because every SDN object still reports `status: available` —
the bridge exists, so PVE is satisfied — while no tenant VM can get an address
and the fabric IPAM stays empty.

`frr-pythontools` being installed does **not** imply `frr` is. They are separate
packages and only the latter is the routing daemon.
