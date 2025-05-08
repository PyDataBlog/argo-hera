# Project: Argo Hera
# Variables
USER_IP ?= 10.145.85.4
CLUSTER_NAME := test-cluster
NAMESPACE_ARGO := argo
NAMESPACE_EVENTS := argo-events
NAMESPACE_WORKFLOWS := workflows
NAMESPACE_ENVOY := envoy-gateway-system
DOMAIN := $(USER_IP).nip.io
MINIO_USER := minioadmin
MINIO_PASSWORD := minioadmin

FILES_TO_UPDATE_IP := \
    test/test_workflow.py \
    minio-route.yaml \
    hello_world.py \
    etl.py \
    main.py \
    artifacts_passing.py \
    argo-route.yaml \
    retry_workflow.py

# Default target
.PHONY: all
all: update-ip-in-files cluster install-all

# Setup cluster
.PHONY: cluster
cluster:
	@echo "Setting up k3d cluster..."
	k3d cluster list | grep $(CLUSTER_NAME) || k3d cluster create $(CLUSTER_NAME) --k3s-arg "--disable=traefik@server:*" -p "80:80@loadbalancer" --servers 1 --agents 3
	k3d kubeconfig merge $(CLUSTER_NAME) --kubeconfig-switch-context
	kubectl get namespace $(NAMESPACE_ARGO) || kubectl create namespace $(NAMESPACE_ARGO)

# Install all components
.PHONY: install-all
install-all: install-envoy install-minio install-argo-events install-argo

# Install Envoy
.PHONY: install-envoy
install-envoy:
	@echo "Installing Envoy Gateway..."
	helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.3.2 -n $(NAMESPACE_ENVOY) --create-namespace --set deployment.replicas=2
	kubectl apply -f eg.yaml
	kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

# Install MinIO
.PHONY: install-minio
install-minio:
	@echo "Installing MinIO..."
	helm repo add minio https://charts.min.io/
	helm repo update
	helm install argo-artifacts minio/minio -f minio-values.yaml -n $(NAMESPACE_ARGO)
	kubectl apply -f minio-route.yaml
	# mc alias set minio-k8s http://minio.$(DOMAIN) $(MINIO_USER) $(MINIO_PASSWORD)
	# mc mb minio-k8s/argo-artifacts

# Install Argo Events
.PHONY: install-argo-events
install-argo-events:
	@echo "Installing Argo Events..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	kubectl apply -k "https://github.com/argoproj/argo-cd/manifests/crds?ref=stable"
	helm install argo-events argo/argo-events -n $(NAMESPACE_EVENTS) --create-namespace
	kubectl apply -n $(NAMESPACE_EVENTS) -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

# Install Argo Workflows
.PHONY: install-argo
install-argo:
	@echo "Installing Argo Workflows..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	kubectl create ns $(NAMESPACE_WORKFLOWS)
	helm upgrade --install wf argo/argo-workflows -n $(NAMESPACE_ARGO) -f argo-values.yaml
	kubectl apply -f argo-route.yaml
	kubectl apply -f argo-roles.yaml

# Update IP in project files
.PHONY: update-ip-in-files
update-ip-in-files:
	@echo "Updating IP address to $(USER_IP) in specified files..."
	@for file in $(FILES_TO_UPDATE_IP); do \
		echo "Updating IP in $$file..."; \
		sed -i 's/10\\.145\\.85\\.4/$(USER_IP)/g' $$file; \
	done
	@echo "IP address update complete in files."

# Run sample workflow
.PHONY: run-sample
run-sample:
	@echo "Running sample workflow..."
	ARGO_SERVER='argo.$(DOMAIN)' \
	ARGO_HTTP1=true \
	ARGO_SECURE=false \
	ARGO_BASE_HREF= \
	ARGO_TOKEN='' \
	argo submit -n $(NAMESPACE_ARGO) --watch sample-workflow.yaml

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all            - Set up cluster and install all components (default)"
	@echo "  cluster        - Set up k3d cluster"
	@echo "  install-all    - Install all components"
	@echo "  install-envoy  - Install Envoy Gateway"
	@echo "  install-minio  - Install MinIO"
	@echo "  install-argo-events - Install Argo Events"
	@echo "  install-argo   - Install Argo Workflows"
	@echo "  run-sample     - Run sample Argo workflow"
	@echo "  help           - Show this help message"

