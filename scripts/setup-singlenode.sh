#!/bin/bash
set -eo pipefail

NAMESPACE=${1:-"authority"}
DOMAIN_SUFFIX=${2:-"ds.helsinki.tfds.io"}

echo "========================================================"
echo " Single Node Setup - $NAMESPACE"
echo "========================================================"

echo "-> Patching tier2-gateway service to ClusterIP..."
kubectl patch svc tier2-gateway -n "$NAMESPACE" -p '{"spec": {"type": "ClusterIP"}}' || {
  echo "WARNING: Failed to patch tier2-gateway. Is it deployed yet?"
}

echo "-> Applying single-node SSL passthrough Ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tier2-gateway-passthrough
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - tls.authority.$NAMESPACE.$DOMAIN_SUFFIX
  rules:
  - host: tls.authority.$NAMESPACE.$DOMAIN_SUFFIX
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tier2-gateway
            port:
              number: 443
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neo4j-browser-ingress
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: dev-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - catalogue-db.authority.$NAMESPACE.$DOMAIN_SUFFIX
    secretName: neo4j-browser-tls
  rules:
  - host: catalogue-db.authority.$NAMESPACE.$DOMAIN_SUFFIX
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: xsfc-neo4j-db-lb-neo4j
            port:
              number: 7474
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "7687": "$NAMESPACE/xsfc-neo4j-db-lb-neo4j:7687"
EOF

echo "-> Setup complete for $NAMESPACE!"
