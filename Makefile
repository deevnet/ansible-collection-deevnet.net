.PHONY: help default deps deps-force build install-dev install-user rebuild publish \
        dns dhcp vyos switch opnsense \
        preflight postcheck \
        migration-opnsense-vlans migration-switch-vlans migration-switch-trunk \
        migration-opnsense-assign migration-opnsense-temp-fw \
        migration-switch-mgmt-ip migration-builder-network migration-builder-port-move \
        migration-switch-test-port migration-opnsense-dhcp \
        migration-opnsense-interfaces migration-opnsense-firewall \
        migration-switch-access-ports migration-switch-trunk-pvid \
        list clean-deps clean-project deep-clean all

# ---------- Config ----------
COLLECTION_NAME ?= deevnet-net
REQS           ?= collections/requirements.yml
DEPS_STAMP     ?= .deps.stamp

# ---------- Migration log capture ----------
MIGRATION_LOG_DIR ?= ./migration-logs
MIGRATION_TS      = $(shell date +%Y%m%d-%H%M%S)

# Post-cutover migration inventory (target IPs).
# After the builder moves to VLAN 99, the default dvntm inventory has
# unreachable IPs. All post-cutover targets use dvntm-new instead.
MIGRATION_INV     ?= ../ansible-inventory-deevnet/dvntm-new

# User-level collections (shared across repos)
USER_COLLECTIONS_PATH    ?= $(HOME)/.ansible/collections

# Project-local collections (this repo only)
PROJECT_COLLECTIONS_PATH ?= ./.ansible/collections

default: help

help:
	@printf "%s\n" \
"Targets:" \
"" \
"  deps" \
"      Install Python packages (requirements.txt) and Galaxy collections (~/.ansible/collections)" \
"      Only runs when requirements files change" \
"" \
"  deps-force" \
"      Force reinstall Python packages and Galaxy collections" \
"" \
"  build" \
"      Build the local collection into a versioned .tar.gz artifact" \
"" \
"  install-dev" \
"      Build and install the collection into ./.ansible/collections (this repo only)" \
"" \
"  install-user" \
"      Build and install the collection into ~/.ansible/collections (for other repos)" \
"" \
"  publish" \
"      deps + build + install-user (user-level publish, not system-wide)" \
"" \
"  rebuild" \
"      deps + install-dev" \
"" \
"  dns" \
"      Configure OPNsense DNS (decrypt inventory vault files first: cd ansible-inventory-deevnet && make unvault)" \
"" \
"  dhcp" \
"      Configure OPNsense DHCP static reservations (decrypt inventory vault files first: cd ansible-inventory-deevnet && make unvault)" \
"" \
"  vyos" \
"      Configure VyOS routers (DNS, DHCP, firewall)" \
"" \
"  switch" \
"      Configure switch VLANs (decrypt inventory vault files first: cd ansible-inventory-deevnet && make unvault)" \
"" \
"  preflight                      Run pre-migration connectivity and readiness checks (read-only)" \
"  postcheck                      Run post-migration validation checks (read-only, uses dvntm-new)" \
"" \
"  migration-opnsense-vlans       Phase 1: Create VLAN interfaces on OPNsense" \
"  migration-switch-vlans        Phase 2: Create VLANs in switch database" \
"  migration-switch-trunk        Phase 3: Configure trunk uplink to router" \
"  migration-opnsense-assign    Step 5a: Assign VLAN devices to OPNsense interfaces + configure IPs" \
"  migration-opnsense-temp-fw   Step 5a2: Temp pass-all firewall rules on VLAN interfaces" \
"  migration-switch-mgmt-ip     Step 5b: Add VLAN 99 mgmt IP to switch (dual-homed)" \
"  migration-builder-network   Step 5c: Configure builder eth0 for target VLAN (expects BUILDER_CURRENT_IP)" \
"  migration-builder-port-move Step 5d: Move builder port to VLAN 99 (temp IP workaround)" \
"  migration-switch-test-port    Phase 4: Move one port to test VLAN" \
"  migration-opnsense-dhcp       Phase 5: Configure DHCP for new subnets" \
"  migration-opnsense-interfaces Phase 6: Assign IPs to VLAN interfaces" \
"  migration-opnsense-firewall   Phase 7: Configure inter-VLAN firewall rules" \
"  migration-switch-access-ports Phase 8: Move remaining ports to VLANs" \
"  migration-switch-trunk-pvid  Phase 9: Set trunk PVID to blackhole (after OPNsense interfaces)" \
"" \
"  Migration logs are captured in $(MIGRATION_LOG_DIR)/ with timestamps." \
"" \
"  list" \
"      Show installed collections in project and user paths" \
"" \
"  clean-deps" \
"      Remove dependency stamp (forces deps next time)" \
"" \
"  clean-project" \
"      Remove project-local collection install" \
"" \
"  deep-clean" \
"      Remove project + user collections and deps stamp"

# ---------- Deps ----------
$(DEPS_STAMP): $(REQS) requirements.txt
	python3 -m pip install --user -q -r requirements.txt
	ansible-galaxy collection install -r "$(REQS)" -p "$(USER_COLLECTIONS_PATH)"
	touch "$(DEPS_STAMP)"

deps: $(DEPS_STAMP)

deps-force:
	python3 -m pip install --user -q -r requirements.txt
	ansible-galaxy collection install -r "$(REQS)" --force -p "$(USER_COLLECTIONS_PATH)"
	touch "$(DEPS_STAMP)"

# ---------- Build ----------
build:
	ansible-galaxy collection build --force

# ---------- Install lanes ----------
install-dev: build
	@mkdir -p "$(PROJECT_COLLECTIONS_PATH)"
	@tarball="$$(ls -1t "$(COLLECTION_NAME)"-*.tar.gz 2>/dev/null | head -1)"; \
	test -n "$$tarball"; \
	echo "Installing tarball (dev): $$tarball"; \
	ansible-galaxy collection install "$$tarball" --force -p "$(PROJECT_COLLECTIONS_PATH)"

install-user: build
	@mkdir -p "$(USER_COLLECTIONS_PATH)"
	@tarball="$$(ls -1t "$(COLLECTION_NAME)"-*.tar.gz 2>/dev/null | head -1)"; \
	test -n "$$tarball"; \
	echo "Installing tarball (user): $$tarball"; \
	ansible-galaxy collection install "$$tarball" --force -p "$(USER_COLLECTIONS_PATH)"

# ---------- Workflows ----------
rebuild: deps install-dev

publish: deps install-user
	@echo "Published $(COLLECTION_NAME) to $(USER_COLLECTIONS_PATH)"

dns: install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/dns.yml

dhcp: install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/dhcp.yml

opnsense: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/opnsense.yml

vyos: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/vyos-site.yml

# ---------- Inspection ----------
list:
	@echo "== Project collections ($(PROJECT_COLLECTIONS_PATH)) =="
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH)" ansible-galaxy collection list || true
	@echo
	@echo "== User collections ($(USER_COLLECTIONS_PATH)) =="
	@ANSIBLE_COLLECTIONS_PATH="$(USER_COLLECTIONS_PATH)" ansible-galaxy collection list || true

# ---------- Cleanup ----------
clean-deps:
	rm -f "$(DEPS_STAMP)"

clean-project:
	rm -rf "$(PROJECT_COLLECTIONS_PATH)"

deep-clean: clean-project
	rm -rf "$(USER_COLLECTIONS_PATH)"
	rm -f "$(DEPS_STAMP)"

# ---------- Switch ----------
switch: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/switch-vlans.yml

# ---------- Pre-flight ----------
preflight: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/00-preflight.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-preflight.log"

# ---------- Post-migration validation ----------
postcheck: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/99-postcheck.yml \
	  -i ../ansible-inventory-deevnet/dvntm-new 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-postcheck.log"

# ---------- Migration (run in sequence, see migration runbook) ----------
# Migration targets use the default inventory (dvntm) which has target VLAN
# definitions layered in with current host IPs. After migration completes,
# dvntm-new (with target IPs) replaces dvntm (Phase 7).
migration-opnsense-vlans: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/01-opnsense-vlans.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-vlans.log"

migration-switch-vlans: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/02-switch-vlans.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-vlans.log"

migration-switch-trunk: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/03-switch-trunk.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-trunk.log"

migration-opnsense-temp-fw: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05e-opnsense-temp-firewall.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-temp-fw.log"

migration-builder-port-move: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05d-builder-port-move.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-builder-port-move.log"

migration-builder-network: deps install-dev
	@echo "Ensuring deevnet.builder collection is installed..."
	@cd ../ansible-collection-deevnet.builder && make publish
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05b-builder-network.yml \
	  -i ../ansible-inventory-deevnet/dvntm-new \
	  -e "ansible_host=$(BUILDER_CURRENT_IP)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-builder-network.log"; true

migration-opnsense-assign: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05-opnsense-assign-interfaces.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-assign.log"

migration-switch-mgmt-ip: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05a-switch-dual-mgmt.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-mgmt-ip.log"

migration-switch-test-port: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/04-switch-test-port.yml 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-test-port.log"

migration-opnsense-dhcp: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05-opnsense-dhcp.yml \
	  -i "$(MIGRATION_INV)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-dhcp.log"

migration-opnsense-interfaces: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/06-opnsense-interfaces.yml \
	  -i "$(MIGRATION_INV)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-interfaces.log"

migration-opnsense-firewall: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/07-opnsense-firewall.yml \
	  -i "$(MIGRATION_INV)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-opnsense-firewall.log"

migration-switch-access-ports: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/08-switch-access-ports.yml \
	  -i "$(MIGRATION_INV)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-access-ports.log"

migration-switch-trunk-pvid: deps install-dev
	@mkdir -p "$(MIGRATION_LOG_DIR)"
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/09-switch-trunk-pvid.yml \
	  -i "$(MIGRATION_INV)" 2>&1 \
	  | tee "$(MIGRATION_LOG_DIR)/$(MIGRATION_TS)-migration-switch-trunk-pvid.log"

all: rebuild dns dhcp
