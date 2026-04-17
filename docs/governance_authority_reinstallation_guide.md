# Governance Authority Reinstallation Guide

This guide outlines the procedure to perform a "factory reset" on the Governance Authority (GA) agent. This process will completely remove the existing Certification Authority (CA) and the Governance Authority's participant identity, allowing you to reinstall them from scratch.

> **⚠️ CRITICAL WARNING:**  
> **Do not perform this operation in a production environment.** Wiping the CA and Identity Provider databases is a highly destructive action. 
> * All previously issued certificates for all onboarded participants and Tier-2 gateways will immediately become invalid.
> * All registered users and participants will be permanently deleted.
> * Every agent in the data space will need to be completely re-onboarded.

---

## 1. The "Remove" Phase (Wiping the State)

The Governance Authority stores its persistent state (PKI, participants, and keys) across three specific PostgreSQL databases. To remove the GA, you must drop these databases.

### Step 1.1: Drop the Databases
Connect to your PostgreSQL instance (either via the deployed `pgadmin` UI or by executing a shell directly in the PostgreSQL pod) and execute the following SQL commands:

```sql
DROP DATABASE ejbca;
DROP DATABASE identity_provider;
DROP DATABASE authentication_provider;
```
*(Note: If your environment uses a shared database cluster, these databases may be prefixed with your namespace, e.g., `authority_ejbca`.)*

### Step 1.2: Wipe the Stale PKI Secrets
When EJBCA creates a fresh database, it generates a brand new `ManagementCA` and API certificates. However, the old certificates are still cached in Kubernetes secrets. If these are not deleted, the Identity Provider will mount the old truststore and fail to communicate with EJBCA (resulting in `PKIX path building failed` errors).

Delete the stale secrets:
```bash
kubectl delete secret ejbca-rest-api-secret -n <authority-namespace> --ignore-not-found
kubectl delete secret ejbca-superadmin -n <authority-namespace> --ignore-not-found
```

### Step 1.3: Recreate Empty Databases (Common Namespace)
In the SIMPL-Open architecture, databases are managed by the Zalando Postgres Operator in the Common Components. After manually dropping the databases, you must restart the operator so it can detect the missing databases, recreate them as empty shells, and regenerate the connection credentials.

```bash
# Note: Replace 'common' with your actual Common Components namespace
kubectl rollout restart deployment pg-operator-common -n common
```

Wait a few moments for the operator to synchronize and create the databases.

### Step 1.3: Restart the Authority Pods
Now that the empty databases exist again, you must restart the affected applications. Upon restarting, the applications will automatically connect to PostgreSQL and execute their internal database migrations (e.g., Flyway/Liquibase) to rebuild their table structures from scratch.

```bash
kubectl rollout restart deployment ejbca-community-helm -n <authority-namespace>
kubectl rollout restart deployment identity-provider -n <authority-namespace>
kubectl rollout restart deployment authentication-provider -n <authority-namespace>
```

---

## 2. The "Reinstall" Phase

Once the pods have restarted and re-initialized their empty databases, the Governance Authority must be reconfigured and issued a new mTLS credential.

### Option A: Automated Reinstallation (Recommended)

If your deployment utilizes an automated initialization Helm hook (e.g., an `agent-init-job` tied to `post-install` and `post-upgrade`), the reinstallation process requires minimal intervention.

1. **Trigger a Helm Upgrade / Sync:**
   Since the databases are now empty, you can trigger your initialization script by forcing a Helm upgrade or an ArgoCD sync.

   ```bash
   # If using ArgoCD:
   argocd app sync <authority-app-name> --force

   # If using Helm manually:
   helm upgrade authority ./charts -n <authority-namespace> --reuse-values
   ```

2. **Verify the Logs:**
   Monitor the logs of the automated job to ensure the keypair was generated, the CSR was signed, and the participant was successfully created.
   ```bash
   kubectl logs job/agent-init-job -n <authority-namespace>
   ```

---

### Option B: Manual Reinstallation

If you do not have an automated initialization job, you must manually rebuild the PKI hierarchy and initialize the participant using the REST APIs.

#### Step 2.1: Reconfigure EJBCA (The PKI Hierarchy)
You must manually recreate the Root CA and Sub CA via the EJBCA Admin Web UI.
1. Access the EJBCA Admin Web UI using the newly generated SuperAdmin credential (found in the EJBCA pod logs).
2. **Create the Root CA** (`SimplCA`) using the ECDSA P-256 algorithm.
3. **Create the Sub CA** (`OnBoardingCA`) signed by the Root CA.
4. **Create the End Entity Profiles** (`Onboarding TLS Profile`) configured to issue Server and Client Authentication certificates.
*(Reference the official `EJBCA.md` documentation for exact parameter values).*

#### Step 2.2: Initialize the Governance Authority Participant
Port-forward the required APIs to your local machine:
```bash
kubectl port-forward svc/authentication-provider 8080:8080 -n <authority-namespace> &
kubectl port-forward svc/identity-provider 8090:8080 -n <authority-namespace> &

export AUTHORITY_AUTH_PROVIDER=localhost:8080
export AUTHORITY_IDENTITY_PROVIDER=localhost:8090
```

Execute the following commands to generate the identity and acquire the signed mTLS certificate:

```bash
# 1. Generate the internal keypair
curl -X POST "$AUTHORITY_AUTH_PROVIDER/v1/keypairs/generate"

# 2. Generate the CSR
curl -X POST "$AUTHORITY_AUTH_PROVIDER/v1/csr/generate" \
--header 'Content-Type: application/json' \
--data-raw '{
  "commonName": "tls.authority.<namespace>.<domain>",
  "country": "FI",
  "organization": "Your Governance Authority",
  "organizationalUnit": "IT"
}' > csr.pem

# 3. Create the GA Participant in the Identity Provider
PARTICIPANT_ID=$(curl -s -X POST "$AUTHORITY_IDENTITY_PROVIDER/v1/participants" \
--header 'Content-Type: application/json' \
--data-raw '{
  "organization": "Your Governance Authority",
  "participantType": "GOVERNANCE_AUTHORITY"
}' | sed -E 's/^"(.*)"$/\1/')

# 4. Upload the CSR for signing
curl -X POST "$AUTHORITY_IDENTITY_PROVIDER/v1/participants/$PARTICIPANT_ID/csr" \
  -F "csr=@csr.pem"

# 5. Download the minted mTLS certificate
curl -s "$AUTHORITY_IDENTITY_PROVIDER/v1/credentials/$PARTICIPANT_ID/download" \
  -o cert.pem

# 6. Load the certificate into the Authentication Provider
curl -X POST "$AUTHORITY_AUTH_PROVIDER/v1/credentials" \
  -F "credential=@cert.pem"
```

## 3. Verification
Once the reinstallation (automated or manual) is complete, the Governance Authority will be operational with a fresh CA and a new participant ID. You can verify functionality by attempting to onboard a new data space participant using the IAA portal.
