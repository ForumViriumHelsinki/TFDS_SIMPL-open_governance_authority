# TFDS SIMPL-open Governance Authority Agent

> **Notice: TFDS Project Fork**
> This repository is a GitOps-optimized fork maintained by the TFDS Project. 
> 
> **Modifications:**
> - Integrated an automated `singleNode` toggle to adapt the multi-IP LoadBalancer architecture for single-IP environments (like k3s) by converting services to `ClusterIP` and dynamically injecting raw TCP/SSL-passthrough routing rules.
> - Substituted upstream dependencies (e.g., the Authentication Provider) with TFDS-maintained GitOps forks to eliminate declarative synchronization drift in ArgoCD caused by dynamically generated Job names.
>
> *The core SIMPL applications are unmodified and dynamically pulled from official registries.*

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

4. **Organization and Initialization:** These variables are injected directly into the automated `agent-init-job` to dynamically configure your cryptographic identity. They must reflect your data space's exact organizational structure.
   ```yaml
   organization:
     name: "FVH"                      # The primary name of your organization
     unit: "Data"                     # The specific organizational unit
     country: "FI"                    # The two-letter ISO country code
   ```

5. **Monitoring:** Configure the logging and metrics integration:
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

### Step 4: Post-Install Configuration (Schema & Vocabulary Loading)

After the Governance Authority is successfully deployed and initialized, the **data space schema shapes** and **vocabularies (ontology)** must be loaded into the internal Federated Catalogue (`xsfc-service`). Without these definitions, participants in the data space will not be able to generate or validate Self-Descriptions (SDs) properly via the SD-Tooling UI.

#### Automated Seeding via Helm Hooks
In this repository, this process has been fully automated. The modified `charts/templates/import-ttl.yaml` file contains a Kubernetes Job (`import-ttl-job`) attached to the `post-install` and `post-upgrade` Helm hooks. 

Once the catalogue is online, this job automatically downloads the required `.ttl` files (Turtle format) and seeds them into the internal API.

#### Architectural Design: Separation of Core and TFDS Customisations
In order to maintain strict interoperability while allowing domain-specific flexibility,
this repository separates the schemas into two distinct layers.

The seeding job loads the schemas in a strict, specific order:

1. **`simpl_ontology.ttl` & `simpl_shapes.ttl`**: 
    * These are the *Core SIMPL-Open schemas*. They define the foundational, domain-agnostic concepts (e.g., standard `Participant`, `DataOffering`). 
2. **`tfds_ontology.ttl` & `tfds_shapes.ttl`**: 
    * These are the *Custom TFDS extensions*. They build upon the core concepts to add Smart City/Helsinki-specific properties and validation rules.

**Why this approach?**
* **Interoperability (Federation):** By preserving the unmodified core SIMPL schemas, the TFDS data space ensures it remains fully compatible with other European Gaia-X / SIMPL data spaces. Other ecosystems will still be able to read and understand the base properties of TFDS offerings.
* **Maintainability:** When the central SIMPL-Open project releases an update to their core ontology, we can seamlessly upgrade the base `.ttl` files without accidentally overwriting or losing the custom TFDS business logic.
* **Idempotency:** The seeding script is designed to safely `POST` the schemas. If the catalogue returns a conflict (meaning the schema already exists), it safely skips it rather than forcing an overwrite (`PUT`). This protects existing, live Self-Descriptions from being invalidated by accidental schema mutations during routine deployments.

#### Customizing Data Space Schemas
This repository is designed to act as a template. If your data space requires further custom schemas:

1. **Update the Download URLs:** Edit `charts/templates/import-ttl.yaml` to point the `BASE_RAW_URL` to your own Git repository containing your custom compiled `.ttl` extension files.
2. **Air-gapped Environments:** If your cluster does not have outbound internet access, you must modify `import-ttl.yaml` to mount the `.ttl` files directly into the Job via a Kubernetes `ConfigMap` rather than downloading them live over the internet.

#### Validating schema insertion.

```shell
curl -s -X GET "http://localhost:8081/schemas" -H "Accept: application/json" | jq '{
    "ontologies_count": (.ontologies | length),
    "ontologies": .ontologies,
    "shapes_count": (.shapes | length),
    "shapes": .shapes
}'
```

---

### Automated Agent Initialization (Post-Install)

Once the Governance Authority stack is fully deployed and the backend APIs (Authentication Provider and Identity Provider) are healthy, the cluster must automatically initialize its own cryptographic identity (Keypairs, CSRs, and signed Credentials) to participate in the data space.

In this repository, **this initialization is 100% automated.**

An ephemeral Kubernetes Job (`agent-init-job`) is deployed via ArgoCD as a Helm `post-install` / `post-upgrade` hook. It handles the entire SIMPL identity bootstrap process without any manual scripts required.

#### How it Works:
1. **Dynamic Configuration:** The Job reads the organizational parameters (`organization.name`, `organization.unit`, `organization.country`, and `domainSuffix`) directly from the top-level `ArgoCD/governance_authority_manifest.yaml`.
2. **Robust Polling:** The script pings the internal Spring Boot APIs until they return valid HTTP responses, ensuring it never attempts to create credentials before the databases are ready.
3. **Idempotent Execution:** The workflow is perfectly safe to run multiple times. If the Job executes during a routine ArgoCD sync and the Participant or Keypair already exists, the script catches the HTTP conflict, prints an informative `(Keypair may already exist)` message to the logs, retrieves the existing IDs, and continues safely.
4. **Self-Cleaning:** Once the initialization completes successfully, the Job pod automatically deletes itself from the cluster (`hook-succeeded`), keeping your namespace clean.
