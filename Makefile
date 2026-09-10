.DEFAULT_GOAL := help
SHELL := /bin/bash

TF      := terraform -chdir=terraform
REGION  ?= us-central1
ZONE    ?= us-central1-a
CLUSTER ?= data-platform

.PHONY: help
help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- Terraform ---------------------------------------------------------------

.PHONY: bootstrap-state
bootstrap-state: ## Create the GCS bucket holding Terraform state (run once, needs PROJECT_ID)
	@test -n "$(PROJECT_ID)" || { echo "PROJECT_ID is required"; exit 1; }
	gcloud storage buckets create gs://$(PROJECT_ID)-tfstate \
		--project=$(PROJECT_ID) \
		--location=$(REGION) \
		--uniform-bucket-level-access
	gcloud storage buckets update gs://$(PROJECT_ID)-tfstate --versioning

.PHONY: grant-deployer
grant-deployer: ## Grant the deployer service account the roles Terraform needs (PROJECT_ID, DEPLOYER_SA)
	@test -n "$(PROJECT_ID)"  || { echo "PROJECT_ID is required";  exit 1; }
	@test -n "$(DEPLOYER_SA)" || { echo "DEPLOYER_SA is required (full email)"; exit 1; }
	@# Terraform cannot grant the identity it authenticates as, so this bootstrap step runs through
	@# gcloud. Once it succeeds, set deployer_service_account_email in terraform.tfvars and the same
	@# bindings become managed declaratively.
	@for role in $(shell $(TF) output -json deployer_roles 2>/dev/null | tr -d '[]"' | tr ',' ' '); do \
		echo "granting $$role"; \
		gcloud projects add-iam-policy-binding $(PROJECT_ID) \
			--member="serviceAccount:$(DEPLOYER_SA)" --role="$$role" \
			--condition=None --quiet > /dev/null; \
	done
	@# Budgets live on the billing account, not the project. This is the grant that most often gets
	@# missed, and the resulting failure surfaces late in the first apply.
	@test -n "$(BILLING_ACCOUNT_ID)" || { \
		echo; echo "WARNING: BILLING_ACCOUNT_ID not set — skipped roles/billing.costsManager."; \
		echo "The budget resource will fail on apply without it."; exit 0; }
	gcloud billing accounts add-iam-policy-binding $(BILLING_ACCOUNT_ID) \
		--member="serviceAccount:$(DEPLOYER_SA)" --role="roles/billing.costsManager" --quiet

.PHONY: grant-deployer-bootstrap
grant-deployer-bootstrap: ## Same as grant-deployer, before any state exists (reads the role list from HCL)
	@test -n "$(PROJECT_ID)"  || { echo "PROJECT_ID is required";  exit 1; }
	@test -n "$(DEPLOYER_SA)" || { echo "DEPLOYER_SA is required (full email)"; exit 1; }
	@# Chicken-and-egg: the very first apply has no state to read deployer_roles from, so parse the
	@# list straight out of the module source.
	@sed -n '/deployer_roles = \[/,/^  \]/p' terraform/modules/iam/identities.tf \
		| grep -o 'roles/[a-zA-Z.]*' \
		| while read -r role; do \
			echo "granting $$role"; \
			gcloud projects add-iam-policy-binding $(PROJECT_ID) \
				--member="serviceAccount:$(DEPLOYER_SA)" --role="$$role" \
				--condition=None --quiet > /dev/null; \
		done
	@test -n "$(BILLING_ACCOUNT_ID)" || { \
		echo; echo "WARNING: BILLING_ACCOUNT_ID not set — skipped roles/billing.costsManager."; exit 0; }
	gcloud billing accounts add-iam-policy-binding $(BILLING_ACCOUNT_ID) \
		--member="serviceAccount:$(DEPLOYER_SA)" --role="roles/billing.costsManager" --quiet

.PHONY: whoami
whoami: ## Show which identity Terraform will authenticate as
	@if [ -n "$$GOOGLE_APPLICATION_CREDENTIALS" ]; then \
		echo "GOOGLE_APPLICATION_CREDENTIALS=$$GOOGLE_APPLICATION_CREDENTIALS"; \
		test -f "$$GOOGLE_APPLICATION_CREDENTIALS" \
			|| { echo "  -> file does not exist"; exit 1; }; \
		echo -n "  identity: "; \
		grep -o '"client_email"[^,]*' "$$GOOGLE_APPLICATION_CREDENTIALS" | cut -d'"' -f4; \
		case "$$GOOGLE_APPLICATION_CREDENTIALS" in \
			$$PWD*) echo "  -> WARNING: key file is inside the repository. Move it outside.";; \
		esac; \
	else \
		echo "No GOOGLE_APPLICATION_CREDENTIALS set — using your gcloud user credentials:"; \
		gcloud config get-value account; \
	fi

.PHONY: init
init: ## Initialise Terraform
	$(TF) init

.PHONY: fmt
fmt: ## Format Terraform files
	terraform fmt -recursive terraform/

.PHONY: validate
validate: ## Validate Terraform configuration
	$(TF) validate

.PHONY: plan
plan: ## Show the execution plan
	$(TF) plan -out=tfplan

.PHONY: apply
apply: ## Apply the last generated plan
	$(TF) apply tfplan

.PHONY: destroy
destroy: ## Tear down all platform infrastructure
	$(TF) destroy

# --- Cluster -----------------------------------------------------------------

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at the platform cluster
	gcloud container clusters get-credentials $(CLUSTER) --zone $(ZONE)

# `kubectl` hanging with an i/o timeout to the control plane almost always means a new ISP-assigned
# IP, not a broken cluster. This prints the one line of tfvars that needs updating.
.PHONY: myip
myip: ## Show the current public IP in authorized_networks form
	@ip=$$(curl -s --max-time 15 ifconfig.me); \
	 cur=$$(grep -o '[0-9.]*/32' terraform/terraform.tfvars | head -1); \
	 echo "current public IP : $$ip"; \
	 echo "allowlisted in tfvars: $$cur"; \
	 if [ "$$ip/32" = "$$cur" ]; then echo "-> match, no change needed"; \
	 else echo "-> STALE. Set in terraform/terraform.tfvars then re-apply:"; \
	      echo "     cidr_block   = \"$$ip/32\""; fi

# Server-side apply is required, not preferred: ArgoCD's CRDs exceed the 256 KiB annotation limit
# that client-side apply uses to store last-applied-configuration, and plain `kubectl apply` fails.
.PHONY: argocd
argocd: ## Install ArgoCD itself
	kubectl apply --server-side --force-conflicts -k gitops/bootstrap
	kubectl -n argocd rollout status deploy/argocd-server --timeout=6m

# Separate from `argocd` because it depends on the platform repo existing on GitHub. Run it after
# the first push, not before.
.PHONY: argocd-root
argocd-root: ## Apply the app-of-apps root application
	kubectl apply -f gitops/apps/root.yaml

.PHONY: argocd-password
argocd-password: ## Print the initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: argocd-ui
argocd-ui: ## Port-forward the ArgoCD UI to localhost:8080
	kubectl -n argocd port-forward svc/argocd-server 8080:443

# --- Inventory ---------------------------------------------------------------

# Bound to 127.0.0.1 so the inventory is not reachable from the network.
.PHONY: inventory
inventory: ## Serve the GCP inventory at http://localhost:8085
	@echo "Inventory: http://localhost:8085/inventory.html  (ctrl-c to stop)"
	@python3 -m http.server 8085 --bind 127.0.0.1 --directory docs

# --- Diagrams ----------------------------------------------------------------

.PHONY: diagram
diagram: ## Render the architecture diagram to SVG
	@mkdir -p diagrams/out
	d2 --layout=elk --theme=1 diagrams/architecture.d2 diagrams/out/architecture.svg

# --- Checks ------------------------------------------------------------------

.PHONY: lint
lint: ## Run tflint and checkov against the Terraform
	tflint --chdir=terraform --recursive
	checkov -d terraform --quiet --compact

.PHONY: cost
cost: ## Show current-month GCP spend by service
	@gcloud billing accounts list
	@echo "Detailed breakdown: see the cost dashboard on the portfolio hub"
