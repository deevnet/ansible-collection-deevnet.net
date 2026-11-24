# tenant_egress_agent

Renders a default route inside every tenant VRF on the exit node, from the list
the Deevnet API publishes (ADR-0015 §7).

## Why an agent

A tenant's VRF needs a default route pointing at the perimeter. That is FRR
configuration on the hypervisor: node-local state the Proxmox API does not
model, so the API - which builds everything else about a tenant - cannot write
it. The alternative to an agent is giving the API root on a hypervisor, which is
a much larger credential than anything else it holds.

So the exit node pulls. It reads `GET /v1/fabric/egress` with a token that
reads that one route and nothing else, renders `/etc/frr/frr.conf.local`, and
only when the file changes runs `pvesh set /cluster/sdn` (which merges it into
the generated `frr.conf`) and reloads FRR.

## What it guarantees

- **An API outage withdraws nothing.** A failed fetch leaves the file as it is,
  so tenants keep the egress they had. The timer tries again.
- **A removed tenant loses its route** on the next run, because the rendered
  file is the whole list rather than an append.
- **It says what the API answered.** Every failure leaves the file as it is;
  the message and the unit's result tell them apart:

  | The API | The agent logs | The unit |
  |---|---|---|
  | answers 200 | nothing, or `rewrote` when the list changed | succeeds |
  | answers 503 (up, not ready) | `the API is up but not ready (503: <its reason>)` | succeeds, `ExecMainStatus=75` |
  | refuses the token (401, 403) | `the API refused this agent's token` | fails |
  | answers anything else | `the API answered <status>` | fails |
  | gives no answer (network, DNS, TLS, not running) | `cannot reach <url>` | fails |

  A 503 is not a failed unit because nothing on the exit node is wrong and it
  clears on its own (INC-0007). Since API v0.28.1 the list answers while
  OpenBao is sealed, so a 503 now means the API's database is not migrated yet.
- **No churn.** Identical content is not rewritten, so FRR is not reloaded for
  nothing.

## What it needs

| Variable | |
|---|---|
| `tenant_egress_agent_api_url` | the API, e.g. `https://api.mobile.deevnet.net:8080` |
| `tenant_egress_agent_token` | `vault_deevnet_egress_agent_token`, the API's `DEEVNET_AGENT_TOKEN` |
| `tenant_egress_agent_ca_src` | the Deevnet Root CA on the control node, from the inventory (`site_root_ca_file`) |
| `tenant_egress_agent_gateway` | the transit gateway, from `deevnet_vlans` |

## After it runs

Set `proxmox_tenant_egress.agent_managed: true` in the exit node's host_vars, so
`proxmox_node_network` stops writing the same file from the inventory list. The
forwarding sysctl and the transit interface stay with that role: they are the
node's, not a tenant's.
