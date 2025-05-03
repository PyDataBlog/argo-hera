SHELL := /bin/bash
.PHONY: help all cluster-create cluster-delete helm-repos envoy-gateway argo-events minio argo-workflows clean post-install-notes install-prereqs check-prereqs install-homebrew ## Declare all command targets as phony

# --- Configuration Variables ---
K3D_CLUSTER_NAME = test-cluster
ARGO_NAMESPACE = argo
WORKFLOWS_NAMESPACE = workflows
ARGO_EVENTS_NAMESPACE = argo-events
ENVOY_GW_NAMESPACE = envoy-gateway-system

EG_HELM_RELEASE = eg
AE_HELM_RELEASE = argo-events
MINIO_HELM_RELEASE = argo-artifacts
AW_HELM_RELEASE = wf

EG_YAML = eg.yaml
MINIO_VALUES = minio-values.yaml
MINIO_ROUTE_YAML = minio-route.yaml
ARGO_VALUES = argo-values.yaml
ARGO_ROUTE_YAML = argo-route.yaml

ARGO_EVENTS_EVENTBUS_URL = https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

# --- Dynamic IP/Hostname Configuration ---
# Default to localhost (127.0.0.1) which works with k3d's port mapping
# You can override this via command line: make all USER_IP=192.168.1.100
# Or with a real domain: make all USER_IP=my.domain.com
USER_IP ?= 127.0.0.1

# Placeholder used in original YAML files - needed for sed substitution
# This should match the IP part of the hostnames in minio-route.yaml and argo-route.yaml initially
PLACEHOLDER_IP = 192.168.64.26

# Helper function to determine the actual hostname to use
# If USER_IP looks like an IP (contains dots), append .nip.io. Otherwise, use it as is.
IP_REGEX = "\." # Simple check: contains a dot
ifeq ($(shell echo $(USER_IP) | grep -q $(IP_REGEX); echo $$?), 0)
  # Looks like an IP (or potentially a subdomain, but for simplicity, we'll append .nip.io if it has a dot)
  ACTUAL_HOSTNAME = $(USER_IP).nip.io
else
  # Doesn't contain a dot, assume it's meant to be a raw domain
  ACTUAL_HOSTNAME = $(USER_IP)
endif

# Temporary files for substituted routes
MINIO_ROUTE_TMP = $(MINIO_ROUTE_YAML).tmp
ARGO_ROUTE_TMP = $(ARGO_ROUTE_YAML).tmp

# --- Default Target ---
all: install-prereqs cluster-create helm-repos envoy-gateway argo-events minio argo-workflows ## Deploys the complete stack (cluster, envoy, events, minio, workflows)

# --- Help Message ---
help: ## Display this help message
	@echo "Usage: make <target> [USER_IP=<your-ip-or-domain>]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"; print ""} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  USER_IP          The IP address or domain prefix to use for services accessible via Envoy Gateway."
	@echo "                   Defaults to 127.0.0.1 for local k3d access (access via localhost:80)."
	@echo "                   If an IP (contains dots), .nip.io will be appended (e.g., 127.0.0.1 becomes 127.0.0.1.nip.io)."
	@echo "                   If a domain (no dots assumed), it will be used directly (e.g., mydomain.com)."
	@echo "                   Example override: make all USER_IP=192.168.1.100"
	@echo "                   Example override: make all USER_IP=my.cluster.domain.com"

# --- Prerequisites Check & Install ---

install-prereqs: ## Install necessary tools (kubectl, helm, k3d) via Homebrew (if on macOS/Linux)
	@echo "=== Checking and Installing Prerequisites ==="
	# Check for brew and install if necessary
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "Homebrew not found. Attempting to install Homebrew..."; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
		echo "---"; \
		echo "Homebrew installation finished. You might need to open a new terminal session or source your shell profile (e.g., ~/.bashrc, ~/.zshrc) for 'brew' to be available in your PATH."; \
		echo "If 'brew' is not found after this step, please fix your shell environment and run 'make install-prereqs' again."; \
		echo "---"; \
		# Exit to force user to fix PATH if necessary before tool installs proceed
		exit 1; \
	fi
	@echo "Homebrew found."

	# Check if brew command is actually working after install (might need sourcing)
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "Error: 'brew' command not found after installation attempt. Please ensure Homebrew is in your PATH and try again."; \
		exit 1; \
	fi

	# Check and install kubectl
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl not found. Installing kubectl via Homebrew..."; \
		brew install kubectl; \
	else \
		echo "kubectl already installed."; \
	fi

	# Check and install helm
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "helm not found. Installing helm via Homebrew..."; \
		brew install helm; \
	else \
		echo "helm already installed."; \
	fi

	# Check and install k3d
	@if ! command -v k3d >/dev/null 2>&1; then \
		echo "k3d not found. Installing k3d via Homebrew..."; \
		brew install k3d; \
	else \
		echo "k3d already installed."; \
	fi
	@echo "Prerequisite check/installation complete."

check-prereqs: ## Check if necessary tools (kubectl, helm, k3d, brew) are installed
	@echo "=== Checking for Prerequisites ==="
	@command -v brew >/dev/null 2>&1 && echo "brew: Found" || echo "brew: Not Found"
	@command -v kubectl >/dev/null 2>&ll 2>&1 && echo "kubectl: Found" || echo "kubectl: Not Found"
	@command -v helm >/dev/null 2>&1 && echo "helm: Found" || echo "helm: Not Found"
	@command -v k3d >/dev/null 2>&1 && echo "k3d: Found" || echo "k3d: Not Found"
	@echo "Prerequisite check complete."

# --- Setup Steps ---

cluster-create: ## Create the k3d cluster and 'argo' namespace
	@echo "=== Creating k3d cluster $(K3D_CLUSTER_NAME) ==="
	k3d cluster create $(K3D_CLUSTER_NAME) \
		--k3s-arg "--disable=traefik@server:*" \
		-p "80:80@loadbalancer" \
		--servers 1 \
		--agents 3
	k3d kubeconfig merge $(K3D_CLUSTER_NAME) --kubeconfig-switch-context
	@echo "--- Creating namespace $(ARGO_NAMESPACE) ---"
	kubectl create namespace $(ARGO_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

helm-repos: ## Add and update necessary Helm repositories
	@echo "=== Adding/Updating Helm Repositories ==="
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add minio https://charts.minio.io/
	helm repo update

envoy-gateway: ## Install Envoy Gateway and default Gateway config
	@echo "=== Installing Envoy Gateway ==="
	helm install $(EG_HELM_RELEASE) oci://docker.io/envoyproxy/gateway-helm --version v1.3.2 -n $(ENVOY_GW_NAMESPACE) --create-namespace
	@echo "--- Applying Envoy Gateway and Gateway config ---"
	kubectl apply -f $(EG_YAML)
	@echo "Envoy Gateway deployment started. Wait for pods in namespace $(ENVOY_GW_NAMESPACE)."

argo-events: helm-repos ## Install Argo Events and native EventBus
	@echo "=== Installing Argo Events ==="
	helm install $(AE_HELM_RELEASE) argo/argo-events -n $(ARGO_EVENTS_NAMESPACE) --create-namespace
	@echo "--- Applying Argo Events native EventBus ---"
	kubectl apply -n $(ARGO_EVENTS_NAMESPACE) -f $(ARGO_EVENTS_EVENTBUS_URL)
	@echo "Argo Events deployment started. Wait for pods in namespace $(ARGO_EVENTS_NAMESPACE)."

minio: helm-repos ## Install Minio (Object Storage) and HTTPRoute
	@echo "=== Installing Minio (Argo Artifacts) ==="
	helm install $(MINIO_HELM_RELEASE) minio/minio -f $(MINIO_VALUES) -n $(ARGO_NAMESPACE)
	@echo "--- Applying Minio HTTPRoute with hostname minio.$(ACTUAL_HOSTNAME) ---"
	# Substitute the placeholder hostname with the calculated one in the route file
	cat $(MINIO_ROUTE_YAML) | sed "s/minio\.$(PLACEHOLDER_IP)\.nip\.io/minio\.$(ACTUAL_HOSTNAME)/g" > $(MINIO_ROUTE_TMP)
	kubectl apply -f $(MINIO_ROUTE_TMP)
	rm $(MINIO_ROUTE_TMP) # Clean up temporary file
	@echo "Minio deployment started. Wait for pods in namespace $(ARGO_NAMESPACE)."
	@echo "NOTE: Access Minio at http://minio.$(ACTUAL_HOSTNAME)"

argo-workflows: helm-repos ## Install Argo Workflows and HTTPRoute
	@echo "=== Installing Argo Workflows ==="
	@echo "--- Creating namespace $(WORKFLOWS_NAMESPACE) ---"
	kubectl create namespace $(WORKFLOWS_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(AW_HELM_RELEASE) argo/argo-workflows -n $(ARGO_NAMESPACE) -f $(ARGO_VALUES)
	@echo "--- Applying Argo Workflows HTTPRoute with hostname argo.$(ACTUAL_HOSTNAME) ---"
	# Substitute the placeholder hostname with the calculated one in the route file
	cat $(ARGO_ROUTE_YAML) | sed "s/argo\.$(PLACEHOLDER_IP)\.nip\.io/argo\.$(ACTUAL_HOSTNAME)/g" > $(ARGO_ROUTE_TMP)
	kubectl apply -f $(ARGO_ROUTE_TMP)
	rm $(ARGO_ROUTE_TMP) # Clean up temporary file
	@echo "Argo Workflows deployment started. Wait for pods in namespace $(ARGO_NAMESPACE)."
	@echo "NOTE: Access Argo Workflows at http://argo.$(ACTUAL_HOSTNAME)"

# --- Cleanup ---

cluster-delete: ## Delete the k3d cluster
	@echo "=== Deleting k3d cluster $(K3D_CLUSTER_NAME) ==="
	k3d cluster delete $(K3D_CLUSTER_NAME)

clean: cluster-delete ## Clean up cluster and namespaces (Use with caution!)
	@echo "=== Cleaning up namespaces ==="
	kubectl delete namespace $(ARGO_NAMESPACE) --ignore-not-found --wait=false
	kubectl delete namespace $(WORKFLOWS_NAMESPACE) --ignore-not-found --wait=false
	kubectl delete namespace $(ARGO_EVENTS_NAMESPACE) --ignore-not-found --wait=false
	kubectl delete namespace $(ENVOY_GW_NAMESPACE) --ignore-not-found --wait=false
	@echo "Cleanup commands sent. Check cluster status."

# --- Post-Installation Notes (Informational) ---
post-install-notes: ## Display post-installation steps and access info
	@echo "--- Post-Installation Notes ---"
	@echo "1. Access Minio console at: http://minio.$(ACTUAL_HOSTNAME)"
	@echo "   Username: minioadmin"
	@echo "   Password: minioadmin"
	@echo "2. Access Argo Workflows UI at: http://argo.$(ACTUAL_HOSTNAME)"
	@echo "3. Create the 'my-bucket' bucket in Minio for Argo Workflows."
	@echo "4. Wait for all pods in namespaces $(ARGO_NAMESPACE), $(WORKFLOWS_NAMESPACE), $(ARGO_EVENTS_NAMESPACE), and $(ENVOY_GW_NAMESPACE) to be ready."
	@echo ""
	@echo "To customize the IP/domain, use the USER_IP variable:"
	@echo "  Example (using local IP): make all USER_IP=192.168.1.100"
	@echo "  Example (using a real domain): make all USER_IP=my.cluster.domain.com"
	@echo "  Defaulting to local k3d access: make all (uses 127.0.0.1)"
