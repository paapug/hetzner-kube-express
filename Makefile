# Terraform with Ansible-Vault-encrypted secrets.vault.json.
#
# Commit:        secrets.vault.json
# Don't commit:  .vault_pass, .cluster_ssh/
# Share with team: the vault passphrase (e.g. via 1Password)

VAULT_FILE := $(CURDIR)/secrets.vault.json
VAULT_PASS := $(CURDIR)/.vault_pass

.PHONY: vault-setup secrets-edit secrets-view ssh-export init plan apply destroy output fmt validate

vault-setup:
	@chmod +x scripts/vault-setup.sh scripts/tf-vault.sh scripts/export-ssh-key.sh
	@./scripts/vault-setup.sh

secrets-edit: $(VAULT_FILE) $(VAULT_PASS)
	ansible-vault edit --vault-password-file $(VAULT_PASS) $(VAULT_FILE)

secrets-view: $(VAULT_FILE) $(VAULT_PASS)
	@ansible-vault view --vault-password-file $(VAULT_PASS) $(VAULT_FILE)

ssh-export: $(VAULT_FILE) $(VAULT_PASS)
	@./scripts/export-ssh-key.sh

init:
	terraform init

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan: $(VAULT_FILE) $(VAULT_PASS)
	@./scripts/tf-vault.sh plan

apply: $(VAULT_FILE) $(VAULT_PASS)
	@./scripts/tf-vault.sh apply

destroy: $(VAULT_FILE) $(VAULT_PASS)
	@./scripts/tf-vault.sh destroy

output: $(VAULT_FILE) $(VAULT_PASS)
	@./scripts/tf-vault.sh output

$(VAULT_FILE):
	@echo "error: $(VAULT_FILE) missing. Run: make vault-setup" >&2
	@exit 1

$(VAULT_PASS):
	@echo "error: $(VAULT_PASS) missing." >&2
	@echo "  Create it (mode 600) with the shared passphrase, or run: make vault-setup" >&2
	@exit 1
