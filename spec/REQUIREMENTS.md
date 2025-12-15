# Deevnet Network Ansible Collection
## REQUIREMENTS.md — Functional and Non-Functional Requirements

### Project Name
**ansible-collection-deevnet.network** (aka `deevnet.network`)

### Purpose
This collection defines and enforces **Network-as-Code / Config-as-Code** for the Deevnet ecosystem. It is the **authoritative source of truth** for:

- Substrate network topology (dvnt, dvntm)
- Deterministic host identity (MAC → host → IP)
- DHCP/DNS/PXE readiness for provisioning workflows
- Environment-aware service naming and routing assumptions
- Guardrails and preflight checks that prevent “PXE roulette”

This document defines **what the collection must do**, not how it is implemented.

---

## 0. Core Concepts and Definitions

### Substrate Networks
A **substrate** is a physical or logical network environment that hosts infrastructure and workloads.

Deevnet includes at least two substrates:

- **dvnt** (home substrate) — `192.168.2.0/24`
- **dvntm** (mobile substrate) — `192.168.10.0/24`

Each substrate is serviced by its own routing/security boundary (typically its own OPNsense instance) and is treated as an independent environment.

Substrates may be implemented as:
- separate physical networks,
- separate firewall/router instances,
- or separate VLANs on shared switching, with independent L3 boundaries.

### Tenants
A **tenant** is a logical workload namespace that runs on a substrate (e.g., *grooveiq*, *vintronics*, *moneyrouter*). Tenants are **not** substrates.

Tenants may exist on one substrate or be deployable to multiple substrates.

### Service Naming
Service endpoints should be name-based and stable (DNS), not hard-coded to IPs.

Two naming layers are supported:

1. **Substrate-scoped service names** (unambiguous):
   - `artifacts.dvnt.deevnet.net`
   - `artifacts.dvntm.deevnet.net`

2. **Global provisioning alias** (optional, but supported):
   - `artifacts.deevnet.net` → points to the currently “active” substrate for provisioning

---

## 1. Assumptions and Operating Model

Unless explicitly overridden:

- Each substrate has an authoritative DHCP/DNS boundary (commonly OPNsense).
- Some provisioning workflows require a “bootstrap host” that provides:
  - HTTP artifact hosting (keys, ISOs, repo content, etc.)
  - PXE/TFTP services (where applicable)
- Deterministic provisioning is achieved through **MAC → host identity mapping**.
- DNS must be resolvable early in provisioning flows (or a deterministic alternative must exist).

---

## 2. Functional Requirements (FR)

### FR-1: Substrate Topology Definition
The collection **MUST** define and manage substrate network configuration for at least:
- dvnt
- dvntm

Sub-functions:
- Represent each substrate’s IP space, boundaries, and routing assumptions
- Represent substrate-specific DNS zone naming conventions
- Support substrate-specific network services and bootstrapping requirements
- Support modeling substrate networks as separate VLANs where applicable

---

### FR-2: Deterministic Host Identity Mapping
The collection **MUST** support a deterministic mapping of host identity using **MAC addresses**.

Sub-functions:
- Maintain an authoritative mapping of:
  - host identifier (short name)
  - MAC address (L2 identity)
  - assigned IPv4 address (L3 identity)
  - substrate membership (dvnt/dvntm)
- Support a clear separation between:
  - “host identity” (what the device is)
  - “role/profile” (what the device does)

---

### FR-3: DHCP Configuration Management
The collection **MUST** manage DHCP configuration for each substrate.

Sub-functions:
- Configure DHCP static mappings from MAC → IP
- Configure DHCP options required for provisioning workflows (as needed), such as:
  - DNS server
  - router/gateway
  - next-server (PXE)
  - boot filename
- Support DHCP behavior differences per substrate

---

### FR-4: DNS Configuration Management
The collection **MUST** manage DNS for each substrate to support stable, name-based provisioning.

Sub-functions:
- Create and manage substrate-specific DNS records for hosts and services
- Support stable service endpoints such as:
  - `artifacts.<substrate>.deevnet.net`
  - `pxe.<substrate>.deevnet.net` (if used)
- Support an optional global alias:
  - `artifacts.deevnet.net` pointing to the substrate currently authoritative for provisioning
- Ensure DNS behavior aligns with provisioning requirements (resolvable during install/bootstrap)

---

### FR-5: Provisioning Readiness for PXE/Netboot
The collection **MUST** support making a substrate “ready for provisioning.”

Sub-functions:
- Ensure DHCP options required for PXE/netboot are correct (when PXE is in use)
- Ensure the bootstrap host endpoints required by provisioning are reachable
- Ensure service DNS names resolve to the correct IPs inside the substrate
- Support both HTTP-based and TFTP-based provisioning flows (as required by the environment)

---

### FR-6: Authority Modes for Provisioning
The collection **MUST** support two operational authority modes for provisioning workflows:

1. **OPNsense-authoritative mode**
   - Substrate firewall/router provides DHCP and DNS
   - Bootstrap host provides artifacts and (optionally) PXE/TFTP service endpoints

2. **Bootstrap-authoritative mode**
   - Bootstrap host provides DHCP/DNS/PXE locally for one-off or portable provisioning
   - Substrate firewall/router may be absent, unconfigured, or intentionally bypassed

Sub-functions:
- Allow deterministic switching between authority modes by explicit configuration
- Maintain consistent host identity and naming behavior across both modes

---

### FR-7: Guardrails and Preflight Checks
The collection **MUST** provide preflight validation that prevents misconfigured provisioning attempts.

Sub-functions:
- Validate that service names resolve correctly within the substrate
- Validate that required HTTP endpoints are reachable (e.g., retrieving provisioning keys)
- Validate that DHCP reservations match intended MAC→IP assignments
- Fail fast with actionable error information if prerequisites are not met

---

### FR-8: Tenant Namespace Support
The collection **MUST** support a tenant naming model separate from substrates.

Sub-functions:
- Support tenant subdomains and naming patterns such as:
  - `<tenant>.dvnt.deevnet.net`
  - `<tenant>.dvntm.deevnet.net`
- Support future expansion where a tenant may be deployed to either substrate without renaming
- Ensure substrate infrastructure naming remains distinct from tenant naming

---

### FR-9: Declarative Interfaces and Entry Points
The collection **MUST** provide clear entry points for applying network configuration.

Sub-functions:
- Support applying configuration per substrate
- Support applying only specific functional areas (DHCP only, DNS only, PXE only, validation only)
- Support non-interactive execution suitable for automation pipelines

---

### FR-10: Documentation of the Network Contract
The collection **MUST** document the expected “network contract” for Deevnet.

Sub-functions:
- Document substrate boundaries, naming conventions, and authority modes
- Document what provisioning workflows assume from the network layer
- Document the deterministic host identity model (MAC→host→IP)
- Provide examples of recommended DNS naming patterns for services and tenants

---

## 3. Non-Functional Requirements (NFR)

### NFR-1: Idempotency
Applying the same configuration repeatedly **MUST NOT** cause unintended changes.

### NFR-2: Determinism
Given the same source-of-truth mapping and substrate selection, the resulting DHCP/DNS behavior **MUST** be deterministic.

### NFR-3: Separation of Concerns
The network collection **MUST NOT**:
- build OS images
- perform application deployments
- become the implementation home of bootstrap host services (those belong in other collections/roles)

It defines the **network contract** and configures network authorities.

### NFR-4: Environment Safety
The collection **MUST** avoid dangerous implicit behavior.
- No “auto-switching” authority modes without explicit configuration
- No silently changing global aliases without explicit intent

### NFR-5: Auditable Source of Truth
Network identity mappings and environment definitions **MUST** be readable, reviewable, and version-controlled.

### NFR-6: Minimal Coupling
The collection **SHOULD** avoid coupling to any single vendor/tooling approach beyond what is necessary.
(OPNsense integration may be primary, but abstractions should not prevent future providers.)

### NFR-7: Clear Failure Modes
Preflight failures **MUST** be actionable and specific (not generic “something failed”).

### NFR-8: Extensibility
The model **MUST** allow:
- adding new substrates (e.g., dvntlab2)
- adding new tenants
- adding new service endpoints
without breaking existing naming patterns.

---

## 4. Out of Scope

- Building OS images (handled by `deevnet-image-factory`)
- Configuring host-local artifacts/PXE services (handled by builder/bootstrap roles in other collections)
- Application runtime and tenant deployments
- Cloud provisioning

---

## 5. Success Criteria

This collection is successful when:

- A new host can be provisioned deterministically using MAC→IP assignments
- Service names (e.g., artifacts endpoints) are stable and environment-correct
- Switching between dvnt and dvntm does not require editing kickstart or “hard-coded IP” artifacts
- Provisioning readiness can be validated via preflight checks before attempting PXE/netboot
- Substrates remain clean “substrate” constructs, and tenants remain separate logical namespaces

---

## 6. Notes

This document specifies **intent**, not implementation.
Implementation choices may include OPNsense APIs, local DNS overrides, DHCP reservations, or alternate authorities—but must satisfy the FR/NFR contract above.
