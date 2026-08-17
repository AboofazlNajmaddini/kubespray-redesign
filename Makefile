# ── Kubespray Offline Workflow ──────────────────────────────────────────
#
# This Makefile wraps the Ansible playbooks used to build and deploy a
# fully air-gapped Kubernetes cluster with Kubespray 2.31.0.
#
# Typical workflow:
#   1. On a machine WITH internet:
#        make build                          # downloads everything, packs kubespray-offline-bundle.tar.gz
#   2. Copy the tar.gz to the air-gapped target, extract it in the project root
#   3. On the air-gapped target:
#        make setup-rpm                      # (optional) push offline RPM repo to nodes
#        make deploy                         # extract bundle + install the cluster
#
# All deploy targets default to inventory/local/hosts.ini.
# Override with:  make deploy INVENTORY=inventory/remote/hosts.ini
#
# Destructive targets (reset, remove-node) require typing YES twice.
# ────────────────────────────────────────────────────────────────────────

INVENTORY          ?= inventory/local/hosts.ini
INVENTORY_BUILDER  := inventory/offline-builder/hosts.yml
BUNDLE             := offline/kubespray-offline-bundle.tar.gz

.PHONY: help build deploy extract setup-rpm reset scale upgrade remove-node recover

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# ── Offline bundle ─────────────────────────────────────────────────────

build: ## builder: download + pack tar.gz (needs internet)
	ansible-playbook -i $(INVENTORY_BUILDER) playbooks/offline-download.yml -c local

deploy: ## extract bundle + install cluster
	ansible-playbook -i $(INVENTORY) playbooks/cluster.yml -c local

extract: ## extract the offline bundle only (no deploy)
	ansible-playbook -i $(INVENTORY) playbooks/cluster.yml -c local \
		--tags offline --start-at-task "Check if offline bundle tar.gz exists"

# ── Cluster lifecycle ──────────────────────────────────────────────────

setup-rpm: ## push offline RPM repo onto nodes (run before cluster.yml)
	ansible-playbook -i $(INVENTORY) playbooks/offline-rpm-repo.yml -c local

reset: ## destroy the cluster (double confirmation required)
	@echo "⚠  This will DESTROY the entire cluster and delete all data."
	@read -p "Are you sure? Type YES to confirm: " confirm1 && [ "$$confirm1" = "YES" ] || (echo "Aborted." && exit 1)
	@read -p "Last chance – type YES again to proceed: " confirm2 && [ "$$confirm2" = "YES" ] || (echo "Aborted." && exit 1)
	ansible-playbook -i $(INVENTORY) playbooks/reset.yml -c local

scale: ## add/remove nodes (set EXTRA='nodes=newnode1,newnode2')
	ansible-playbook -i $(INVENTORY) playbooks/scale.yml -c local $(EXTRA)

upgrade: ## upgrade cluster to new versions
	ansible-playbook -i $(INVENTORY) playbooks/upgrade_cluster.yml -c local $(EXTRA)

remove-node: ## remove a node (double confirmation, set EXTRA='node=oldnode1')
	@echo "⚠  This will REMOVE the specified node(s) from the cluster."
	@read -p "Are you sure? Type YES to confirm: " confirm1 && [ "$$confirm1" = "YES" ] || (echo "Aborted." && exit 1)
	@read -p "Last chance – type YES again to proceed: " confirm2 && [ "$$confirm2" = "YES" ] || (echo "Aborted." && exit 1)
	ansible-playbook -i $(INVENTORY) playbooks/remove_node.yml -c local $(EXTRA)

recover: ## recover control plane (etcd + API server)
	ansible-playbook -i $(INVENTORY) playbooks/recover_control_plane.yml -c local
