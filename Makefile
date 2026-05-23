# Terraform via SOPS-encrypted secrets.enc.json (see secrets.example.json).
export SOPS_AGE_KEY_FILE ?= $(CURDIR)/.age/key.txt
SECRETS_ENC := $(CURDIR)/secrets.enc.json

.PHONY: sops-setup secrets-edit init plan apply destroy output fmt validate

sops-setup:
	@chmod +x scripts/sops-setup.sh scripts/tf-sops.sh
	@./scripts/sops-setup.sh

secrets-edit:
	@test -f "$(SECRETS_ENC)" || (echo "Run: make sops-setup" >&2; exit 1)
	sops "$(SECRETS_ENC)"

init:
	terraform init

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan: $(SECRETS_ENC)
	@./scripts/tf-sops.sh plan

apply: $(SECRETS_ENC)
	@./scripts/tf-sops.sh apply

destroy: $(SECRETS_ENC)
	@./scripts/tf-sops.sh destroy

output: $(SECRETS_ENC)
	@./scripts/tf-sops.sh output

$(SECRETS_ENC):
	@echo "error: $(SECRETS_ENC) missing. Run: make sops-setup" >&2
	@exit 1
