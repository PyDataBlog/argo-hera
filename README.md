# Argo Hera

A sample project demonstrating how to use [Hera](https://argoproj.github.io/argo-workflows/) Python SDK with Argo Workflows running in Kubernetes locally.

## Overview

This project showcases the integration between Argo Workflows and Hera, providing examples of different workflow patterns and capabilities:

- Basic workflow execution
- DAG-based workflows
- Artifact passing between workflow steps
- Workflow retry mechanisms
- ETL pipeline example

## Prerequisites

- Docker
- k3d
- kubectl
- Helm
- Python 3.13+
- uv (Python package manager)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/argo-hera.git
cd argo-hera
```

### 2. Create virtual environment using uv

```bash
uv venv
source .venv/bin/activate
uv pip install -e .
```

### 3. Set up Kubernetes cluster and install components

The project includes a Makefile to automate the setup:

```bash
# check all available commands
make help

# Set up everything (cluster + all components)
make all

# Or step by step:
make cluster
make install-envoy
make install-minio
make install-argo-events
make install-argo
```

This will:

- Create a k3d cluster
- Install Envoy Gateway
- Set up MinIO for artifact storage
- Install Argo Events
- Install Argo Workflows with appropriate configuration

### 4. Setting User IP

The `Makefile` uses a `USER_IP` variable, which defaults to `10.145.85.4`. This IP is used for configuring access to services like MinIO and Argo Workflows.

You can override this IP in two ways:

- **Command-line argument:**
  ```bash
  make USER_IP=your_ip_address <target>
  # Example: make USER_IP=192.168.1.100 all
  ```

- **Environment variable:**
  ```bash
  export USER_IP=your_ip_address
  make <target>
  # Or for a single command:
  # USER_IP=your_ip_address make <target>
  ```

If you don't provide `USER_IP`, the default value will be used.

## Examples

### Hello World Workflow

```bash
python hello_world.py
```

### Diamond DAG Workflow

```bash
python main.py
```

### ETL Pipeline Example

```bash
python etl.py
```

### Artifact Passing Between Tasks

```bash
python artifacts_passing.py
```

### Retrying Failed Tasks

```bash
python retry_workflow.py
```

### Run sample workflow from YAML

```bash
make run-sample
```

## Testing

Run the tests using pytest:

```bash
pytest
```

## Project Structure

- `argo-roles.yaml`: RBAC roles for Argo Workflows
- `argo-route.yaml`: HTTP route for Argo server
- `argo-values.yaml`: Helm values for Argo Workflows
- `minio-values.yaml`: Helm values for MinIO
- `eg.yaml`: Envoy Gateway configuration
- Python examples:
  - `hello_world.py`: Simple workflow example
  - `main.py`: DAG diamond pattern workflow
  - `etl.py`: ETL pipeline example
  - `artifacts_passing.py`: Example of passing artifacts between tasks
  - `retry_workflow.py`: Example of retrying failed tasks
- `test/`: Test files

## Resources

- [Argo Workflows Documentation](https://argoproj.github.io/argo-workflows/)
- [Hera SDK Documentation](https://hera-workflows.readthedocs.io/)
