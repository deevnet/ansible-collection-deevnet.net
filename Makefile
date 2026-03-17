.PHONY: help default deps deps-force build install-dev install-user rebuild publish \
        dns dhcp vyos switch opnsense \
        migration-opnsense-vlans migration-switch-vlans migration-switch-trunk \
        migration-switch-test-port migration-opnsense-dhcp \
        migration-opnsense-interfaces migration-opnsense-firewall \
        migration-switch-access-ports \
        list clean-deps clean-project deep-clean all

# ---------- Config ----------
COLLECTION_NAME ?= deevnet-net
REQS           ?= collections/requirements.yml
DEPS_STAMP     ?= .deps.stamp

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
"  migration-opnsense-vlans       Phase 1: Create VLAN interfaces on OPNsense" \
"  migration-switch-vlans        Phase 2: Create VLANs in switch database" \
"  migration-switch-trunk        Phase 3: Configure trunk uplink to router" \
"  migration-switch-test-port    Phase 4: Move one port to test VLAN" \
"  migration-opnsense-dhcp       Phase 5: Configure DHCP for new subnets" \
"  migration-opnsense-interfaces Phase 6: Assign IPs to VLAN interfaces" \
"  migration-opnsense-firewall   Phase 7: Configure inter-VLAN firewall rules" \
"  migration-switch-access-ports Phase 8: Move remaining ports to VLANs" \
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

# ---------- Migration (run in sequence, see migration runbook) ----------
# Migration targets use the default inventory (dvntm) which has target VLAN
# definitions layered in with current host IPs. After migration completes,
# dvntm-new (with target IPs) replaces dvntm (Phase 7).
migration-opnsense-vlans: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/01-opnsense-vlans.yml

migration-switch-vlans: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/02-switch-vlans.yml

migration-switch-trunk: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/03-switch-trunk.yml

migration-switch-test-port: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/04-switch-test-port.yml

migration-opnsense-dhcp: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/05-opnsense-dhcp.yml

migration-opnsense-interfaces: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/06-opnsense-interfaces.yml

migration-opnsense-firewall: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/07-opnsense-firewall.yml

migration-switch-access-ports: deps install-dev
	@ANSIBLE_COLLECTIONS_PATH="$(PROJECT_COLLECTIONS_PATH):$(USER_COLLECTIONS_PATH)" \
	  ansible-playbook playbooks/migration/08-switch-access-ports.yml

all: rebuild dns dhcp
