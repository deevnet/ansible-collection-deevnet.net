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
| `proxmox_tenant_egress` | Tenant VRF egress: transit forwarding and the leaked default route |

## Tags

Run in this order. The tags exist so the risky step is separable from the safe
ones, not as a convenience.

| Tag | What it does | Risk |
|---|---|---|
| `packages` | Installs `frr` and `dnsmasq` — the daemons that realize the SDN config (**needs SSH**) | None; without them the fabric exists in the API and does nothing |
| `interfaces` | Bridge becomes VLAN-aware; VLAN sub-interfaces created | Additive - nothing loses connectivity |
| `mgmt-routing` | Installs the source-based routing unit (**needs SSH**) | None on its own |
| `default-route` | Moves the default route off management onto transit | **Can cost access** - refuses to run unless `mgmt-routing` is active |
| `tenant-egress` | Forwarding on transit, plus a default route in each tenant VRF (**needs SSH**) | Additive; asserts the routing outcome rather than the write |

```bash
ansible-playbook playbooks/proxmox-node-network.yml --tags packages
ansible-playbook playbooks/proxmox-node-network.yml --tags interfaces
ansible-playbook playbooks/proxmox-node-network.yml --tags mgmt-routing
ansible-playbook playbooks/proxmox-node-network.yml --tags default-route
ansible-playbook playbooks/proxmox-node-network.yml --tags tenant-egress
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

## Why tenant egress needs this role at all

Two node-local settings Proxmox will not manage, and they mask each other.

**Forwarding.** Linux decides whether to forward from the *ingress* interface's
own flag. Proxmox sets `ip-forward on` for the interfaces its SDN config owns -
the VNet bridge, the underlay, the VTEP loopback - so traffic leaving a tenant
was always forwarded correctly. The transit interface is not one of those: it is
node substrate in `/etc/network/interfaces`, and the PVE network API has no
forwarding property (its parser also drops an `ip-forward` line written by
hand), so it comes up with `forwarding=0`.

The result is a one-way path that reads as a routing bug. Requests leave, get
SNATed, reach the internet and are answered - the replies are visible on the
wire and conntrack holds the correct reverse tuple - and the kernel then refuses
to forward them back in. The VM sees 100% loss while the exit node's SNAT
counter climbs, which is exactly the evidence that invites you to conclude
egress is working.

**The VRF default route.** Proxmox generates `default-originate` under
`router bgp <asn> vrf vrf_<tenant>`, which advertises a default to *other* VTEPs
over EVPN and installs nothing locally. On a single-member fabric the only node
is the exit node, so there is no peer to learn from.

Proxmox's own answer is in `EvpnPlugin.pm`: on an exit node it deletes the VRF's
`unreachable default`, so a lookup that misses falls through to the **main**
table. That does give a tenant the internet - and it also sends tenant traffic
bound for the management segment straight out `vmbr0`, on-link, unSNATed, never
passing the perimeter. Measured before the fix: five tenant-sourced packets
captured on the management VLAN with source `10.20.129.10`; zero after.

So the leaked default is policy, not a single-member workaround. The exit node
needs it however many members the fabric has. It is delivered through
`/etc/frr/frr.conf.local`, which Proxmox merges into the config it generates -
its parser folds a bare `vrf <name>` stanza into the generated block, so the
route lands inside Proxmox's own `vrf vrf_<tenant>` section on every SDN apply.

See ADR-0003 in `deevnet-docs`.
