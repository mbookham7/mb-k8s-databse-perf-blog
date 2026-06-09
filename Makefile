# PostgreSQL-on-EKS benchmark demo: WEKA vs. standard block storage.
#
# Override defaults on the command line, e.g.:
#   make infra REGION=us-east-1 CLUSTER_NAME=my-demo
#
# The `weka` target needs Quay.io credentials (from get.weka.io):
#   export QUAY_USERNAME=... QUAY_PASSWORD=...

SHELL := /bin/bash
REGION       ?= eu-west-1
CLUSTER_NAME ?= pg-weka-bench

TF_VPC     := terraform/00-vpc
TF_BACKEND := terraform/10-weka-backend
TF_EKS     := terraform/20-eks

.PHONY: help infra apps all vpc backend eks kubeconfig weka postgres bench \
        destroy clean-apps fmt validate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## ---------------------------------------------------------------------------
## Infrastructure (Terraform) — run in order
## ---------------------------------------------------------------------------
vpc: ## Create the VPC
	terraform -chdir=$(TF_VPC) init -input=false
	terraform -chdir=$(TF_VPC) apply -auto-approve

backend: ## Create the WEKA backend cluster (needs terraform.tfvars)
	terraform -chdir=$(TF_BACKEND) init -input=false
	terraform -chdir=$(TF_BACKEND) apply -auto-approve

eks: ## Create the EKS cluster + EBS CSI driver (needs terraform.tfvars)
	terraform -chdir=$(TF_EKS) init -input=false
	terraform -chdir=$(TF_EKS) apply -auto-approve

infra: vpc backend eks ## Create all infrastructure

kubeconfig: ## Point kubectl at the EKS cluster
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(REGION)

## ---------------------------------------------------------------------------
## Workloads (kubectl / Helm)
## ---------------------------------------------------------------------------
weka: kubeconfig ## Install WEKA operator + CSI + client + StorageClass
	@test -n "$(QUAY_USERNAME)" || { echo "ERROR: set QUAY_USERNAME"; exit 1; }
	@test -n "$(QUAY_PASSWORD)" || { echo "ERROR: set QUAY_PASSWORD"; exit 1; }
	@BN=$$(terraform -chdir=$(TF_BACKEND) output -raw cluster_name); \
	 SA=$$(terraform -chdir=$(TF_BACKEND) output -raw weka_secret_arn); \
	 ./scripts/deploy-weka.sh \
	   --cluster-name $(CLUSTER_NAME) --region $(REGION) \
	   --quay-username "$(QUAY_USERNAME)" --quay-password "$(QUAY_PASSWORD)" \
	   --backend-name "$$BN" --secret-arn "$$SA"

postgres: kubeconfig ## Deploy both PostgreSQL instances + pgbench runner
	kubectl apply -f manifests/postgres/
	kubectl rollout status deploy/postgres-standard -n benchmark --timeout=300s
	kubectl rollout status deploy/postgres-weka -n benchmark --timeout=300s
	kubectl wait --for=condition=Ready pod/pgbench-runner -n benchmark --timeout=180s

apps: weka postgres ## Deploy WEKA stack + PostgreSQL

bench: ## Run the pgbench benchmark and write results/
	./scripts/run-benchmark.sh

all: infra apps bench ## Everything end to end

## ---------------------------------------------------------------------------
## Teardown
## ---------------------------------------------------------------------------
clean-apps: kubeconfig ## Remove PostgreSQL + WEKA components (keep infra)
	kubectl delete -f manifests/postgres/ --ignore-not-found=true
	./scripts/deploy-weka.sh --cleanup --cluster-name $(CLUSTER_NAME) --region $(REGION)

destroy: clean-apps ## Destroy everything (apps, then EKS, backend, VPC)
	terraform -chdir=$(TF_EKS) destroy -auto-approve
	terraform -chdir=$(TF_BACKEND) destroy -auto-approve
	terraform -chdir=$(TF_VPC) destroy -auto-approve

## ---------------------------------------------------------------------------
## Static checks
## ---------------------------------------------------------------------------
fmt: ## terraform fmt across all layers
	terraform fmt -recursive terraform/

validate: ## terraform validate each layer (requires init)
	terraform -chdir=$(TF_VPC) validate
	terraform -chdir=$(TF_BACKEND) validate
	terraform -chdir=$(TF_EKS) validate
