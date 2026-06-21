# Mitigation: Vault Secrets Webhook TLS Certificate Mismatch

## Overview
A known issue exists where pods relying on the Banzai Cloud Vault Secrets Webhook fail to start, becoming stuck in a `CrashLoopBackOff` state due to database authentication failures. 

This occurs when the webhook fails to mutate the pods, leaving literal secret references (e.g., `vault:example/data/...`) in the environment variables instead of injecting the actual passwords. The root cause is a TLS certificate mismatch between the `MutatingWebhookConfiguration` and the webhook's serving certificate, causing the Kubernetes API server to reject the webhook connection.

## Symptoms
1.  Pods (e.g., `keycloak-0`, `authentication-provider`, `users-roles`) are in a `CrashLoopBackOff` state.
2.  Container logs show database authentication errors (e.g., `FATAL: password authentication failed for user`).
3.  Inspecting the failing pod (`kubectl get pod <pod-name> -o yaml`) reveals missing Banzai Cloud `initContainers` (specifically the `vault-env` initialization container).
4.  Checking the webhook logs (`kubectl logs -n common-vswh deployment/vault-webhook-common`) shows continuous `http: TLS handshake error: remote error: tls: bad certificate` errors.

## Mitigation Steps

To resolve this issue, you need to update the `caBundle` in the `MutatingWebhookConfiguration` so the Kubernetes API server trusts the webhook. 

**Proactive Recommendation:** It is highly recommended to perform this patching process *before* deploying your application workloads (e.g., Keycloak, Authentication Provider) to a new cluster or namespace. If the webhook trust is established beforehand, the pods will be mutated on their first start and completely avoid the `CrashLoopBackOff` phase.

Because the automatic `cert-manager` injection has proven unreliable across multiple environments, the **Manual CA Bundle Patching** is currently the primary and most reliable approach.

### Approach 1: Manual CA Bundle Patching (Recommended)

This method directly synchronizes the webhook configuration with the active TLS certificate.

1.  **Extract the current CA Bundle:**
    Extract the base64-encoded `ca.crt` from the webhook's TLS secret:
    ```bash
    kubectl get secret vault-webhook-common-webhook-tls -n common-vswh -o jsonpath="{.data.ca\.crt}"
    ```

2.  **Patch the MutatingWebhookConfiguration:**
    Copy the exact output string from the previous command and substitute it for `<YOUR_BASE64_CA_BUNDLE>` in the following command to patch both webhooks:
    ```bash
    kubectl patch mutatingwebhookconfiguration vault-webhook-common --type='json' -p='[{"op": "replace", "path": "/webhooks/0/clientConfig/caBundle", "value":"<YOUR_BASE64_CA_BUNDLE>"}, {"op": "replace", "path": "/webhooks/1/clientConfig/caBundle", "value":"<YOUR_BASE64_CA_BUNDLE>"}]'
    ```

### Approach 2: Force cert-manager Re-injection (Fallback)

If you prefer to attempt automatic injection, you can try forcing `cert-manager` to resync. This has shown inconsistent results.

1.  **Remove the cert-manager annotation:**
    Remove the `cert-manager.io/inject-ca-from` annotation from the `MutatingWebhookConfiguration`. This clears the stale CA bundle.
    ```bash
    kubectl patch mutatingwebhookconfiguration vault-webhook-common -p '{"metadata":{"annotations":{"cert-manager.io/inject-ca-from":null}}}'
    ```

2.  **Re-apply the cert-manager annotation:**
    Re-add the annotation, pointing it to the correct certificate secret.
    ```bash
    kubectl patch mutatingwebhookconfiguration vault-webhook-common -p '{"metadata":{"annotations":{"cert-manager.io/inject-ca-from":"common-vswh/vault-webhook-common-webhook-tls"}}}'
    ```

### Restart Failing Pods (If Reactively Patching)

If you applied this fix *after* deploying your application and pods are already failing, they need to be restarted. Delete the failing pods to force the Deployment or StatefulSet to recreate them.
```bash
# Example: Restarting Keycloak
kubectl delete pod -n <namespace> keycloak-0

# Or, to restart all failing pods in a namespace:
# First, list them to ensure you are targeting the correct ones
kubectl get pods -n <namespace> | grep CrashLoopBackOff

# Then delete them individually
kubectl delete pod <pod-name-1> <pod-name-2> -n <namespace>
```

## Verification
After restarting a pod, verify the mitigation was successful by checking if the pod contains the injected `vault-env` initialization container:
```bash
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 "initContainers"
```
You should see output similar to this, confirming the webhook successfully mutated the pod:
```yaml
  initContainers:
  - command:
    - sh
    - -c
    - cp /usr/local/bin/vault-env /vault/
    image: ghcr.io/bank-vaults/vault-env:v1.22.1
```