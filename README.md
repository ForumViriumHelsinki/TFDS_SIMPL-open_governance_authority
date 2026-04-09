# TFDS SIMPL-open Governance Authority Agent

This repository contains the deployment manifests and configurations for the **SIMPL-Open Governance Authority** agent. It supports both standard distributed deployments and an **optional local, single-node deployment mode** (e.g., for k3s environments).

## 🚀 Deployment Guide

This guide is designed for users who want to deploy the Governance Authority agent using **ArgoCD**.

### Prerequisites

Before deploying the Governance Authority, ensure your environment meets the following requirements:
1. **Running Kubernetes Cluster:** A standard multi-node cluster or a local single-node cluster (like k3s). Ensure `MetalLB` and an Ingress Controller (e.g., `nginx`) are present.
2. **Common Components Deployed:** The core SIMPL infrastructure (Kafka, PostgreSQL, Elastic, OpenBao) must already be running in the `common` namespace. You can find the deployment guide for this layer in the [Common Components Repository](https://github.com/ForumViriumHelsinki/TFDS_SIMPL-open_common_components).
3. **DNS Routing:** A wildcard DNS record (e.g., `*.authority.yourdomain.com`) pointing to your cluster's public/ingress IP.

---

### Step 1: Configure the ArgoCD Manifest

All configuration for the deployment is managed through a single file: `ArgoCD/governance_authority_manifest.yaml`.

Open this file and verify or update the `values` block to match your environment:

1. **Deployment Mode (Single Node vs Standard):** 
   You can toggle the optional single-node optimizations with the `singleNode` flag:
   ```yaml
   singleNode: true                   # Set to true for lightweight k3s deployments, false for standard
   resourcePreset: low                # Set to "low" to disable strict resource requests
   ```

2. **Namespace Tags:** Update the identifiers for your namespaces:
   ```yaml
   namespaceTag:
     authority: authority             # Your governance authority namespace
     common: common                   # Your common components namespace
   ```

3. **Domain Federation:** Update the domain suffix to match your cluster's base domain:
   ```yaml
   domainSuffix: ds.helsinki.tfds.io  # Your local cluster's base domain
   ```

4. **Monitoring:** Configure the logging and metrics integration:
   ```yaml
   monitoring:
     enabled: false                   # Disable if you are not running the Common monitoring stack
   ```
   *   **Impact if `false`:** Skips attempting to ship metrics/logs. Ensures a clean deployment if you don't have the heavy Elastic monitoring stack running in your `common` namespace.

---

### Step 2: Deploy the Agent

Once your configuration is set, you can trigger the deployment using ArgoCD:

```bash
kubectl apply -f ArgoCD/governance_authority_manifest.yaml
```

ArgoCD will automatically read the configuration and begin spinning up the Governance Authority agent in the specified namespace.

---

### Step 3: Expected Behavior & Trust Anchor Setup

The Governance Authority serves as the primary trust anchor for your data space. After deployment, other agents (like the Data Provider and Data Consumer) will interact with this Authority to receive their business-level certificates and become onboarded participants.

For the full participant onboarding flow, reference the official [SIMPL Open Onboarding Manual (v2.8.x)](https://code.europa.eu/simpl/simpl-open/development/iaa/documentation/-/tree/main/versioned_docs/2.8.x/user-manual/ONBOARD.md?ref_type=heads).
