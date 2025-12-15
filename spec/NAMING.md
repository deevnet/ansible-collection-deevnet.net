# Deevnet Naming Standard
## NAMING.md — Hosts, Services, Tenants, and Environments

### Purpose
This document defines the canonical naming conventions for the Deevnet ecosystem. The goal is to ensure that names are:

- **Deterministic** (predictable, repeatable)
- **Scalable** (works as the lab grows)
- **Readable** (humans can understand intent quickly)
- **Environment-safe** (dvnt vs dvntm is always clear)
- **Service-oriented** (service names are stable even if hosts move)

This naming standard applies to:
- DNS zones and hostnames
- Service endpoints (artifacts, PXE, DNS, etc.)
- Tenants (logical workload namespaces)
- Inventory naming (Ansible host identifiers)

---

## 1. Definitions

### Substrate
A **substrate** is a network environment that hosts systems and workloads.

Current substrates:
- **dvnt** — home substrate
- **dvntm** — mobile substrate

Substrate names are treated as **environment identifiers**, not workloads.

### Tenant
A **tenant** is a logical workload namespace (e.g., grooveiq, vintronics). Tenants may be deployed to one or more substrates.

### Host
A **host** is a physical or virtual system with a deterministic identity (ideally MAC→IP mapping on a substrate network).

### Service
A **service** is a logical endpoint that may move between hosts without changing its public name (e.g., artifacts, pxe).

---

## 2. DNS Zones

### 2.1 Root Zone
- **`deevnet.net`** is the root zone.

### 2.2 Substrate Zones
Each substrate has its own sub-zone:

- **`dvnt.deevnet.net`**
- **`dvntm.deevnet.net`**

All substrate-specific host and service records MUST exist in the corresponding substrate zone.

---

## 3. Host Naming

### 3.1 Hostname Format
Hosts MUST use short, functional hostnames within a substrate zone:

- `<function>-<nn>.<substrate>.deevnet.net`

Examples:
- `admin-02.dvntm.deevnet.net`
- `router-01.dvnt.deevnet.net`
- `proxmox-01.dvnt.deevnet.net`
- `build-01.dvntm.deevnet.net`

### 3.2 Allowed Characters
- Lowercase letters: `a-z`
- Digits: `0-9`
- Hyphen: `-`
- No underscores

### 3.3 Numeric Suffix
Where multiple hosts share a function, two-digit suffixes SHOULD be used:
- `01`, `02`, `03`, …

---

## 4. Service Naming

### 4.1 Service Names are Not Hostnames
A service name MUST remain stable even if the service moves to a different host.

Services SHOULD point to hosts via DNS records (A/AAAA/CNAME).

### 4.2 Substrate-Scoped Service Names (Preferred)
All infrastructure services MUST have a substrate-scoped name:

- `<service>.<substrate>.deevnet.net`

Examples:
- `artifacts.dvntm.deevnet.net`
- `pxe.dvntm.deevnet.net`
- `dns.dvnt.deevnet.net`
- `ntp.dvnt.deevnet.net`
- `vault.dvnt.deevnet.net`

### 4.3 Global Provisioning Alias (Optional)
A global alias MAY exist to point to the currently active provisioning substrate:

- `artifacts.deevnet.net`

Rules:
- The global alias MUST be explicitly controlled by automation (Config-as-Code).
- The global alias MUST NOT change implicitly.
- When used, it SHOULD be a CNAME to the substrate-scoped service:
  - `artifacts.deevnet.net` → `artifacts.dvntm.deevnet.net`

---

## 5. Tenant Naming

### 5.1 Tenant Names are Workload Namespaces
Tenant names MUST be distinct from substrate names.

Examples of tenants:
- `grooveiq`
- `vintronics`
- `moneyrouter`

### 5.2 Tenant DNS Patterns
Tenants SHOULD be expressed under the substrate zone to make placement explicit:

- `<tenant>.<substrate>.deevnet.net`

Examples:
- `grooveiq.dvntm.deevnet.net`
- `vintronics.dvnt.deevnet.net`

### 5.3 Tenant Service Names
Tenant services SHOULD use a subdomain under the tenant namespace:

- `<service>.<tenant>.<substrate>.deevnet.net`

Examples:
- `api.grooveiq.dvntm.deevnet.net`
- `mqtt.grooveiq.dvntm.deevnet.net`
- `web.moneyrouter.dvnt.deevnet.net`

---

## 6. Inventory Naming (Ansible)

### 6.1 Inventory Host Identifiers
Ansible inventory hostnames SHOULD be short and environment-neutral:

Examples:
- `admin-02`
- `proxmox-01`

The environment/substrate association SHOULD be expressed via groups:
- group `dvnt`
- group `dvntm`

### 6.2 Mapping to DNS
Inventory entries SHOULD map cleanly to FQDNs via:
- `inventory_hostname + "." + substrate_zone`

Example:
- `admin-02` in group `dvntm` → `admin-02.dvntm.deevnet.net`

---

## 7. Addressing and Deterministic Identity

### 7.1 Host Identity Source of Truth
Hosts SHOULD be assigned deterministic addresses by mapping:
- MAC → IP → DNS name

This mapping is considered “identity,” not “configuration,” and SHOULD be maintained as Config-as-Code.

### 7.2 Host vs Service Resolution
- Hosts resolve to fixed IPs via A/AAAA records.
- Services resolve to hosts via CNAME (preferred) or A/AAAA.

---

## 8. Examples

### 8.1 dvntm Infrastructure
- Host:
  - `admin-02.dvntm.deevnet.net`
- Services:
  - `artifacts.dvntm.deevnet.net` → `admin-02.dvntm.deevnet.net`
  - `pxe.dvntm.deevnet.net` → `admin-02.dvntm.deevnet.net`

### 8.2 Tenant on dvntm
- Tenant namespace:
  - `grooveiq.dvntm.deevnet.net`
- Tenant services:
  - `mqtt.grooveiq.dvntm.deevnet.net`
  - `api.grooveiq.dvntm.deevnet.net`

### 8.3 Global Provisioning Alias
- `artifacts.deevnet.net` → `artifacts.dvntm.deevnet.net`
- Kickstart and PXE reference:
  - `http://artifacts.deevnet.net/...`

---

## 9. Policy Notes

- Substrate names (`dvnt`, `dvntm`) MUST remain substrate-only identifiers.
- Tenant naming MUST remain workload-only identifiers.
- Hard-coded IPs in provisioning flows SHOULD be treated as defects.
- A global provisioning alias is optional; substrate-scoped names are mandatory.

---
