#!/usr/bin/env bash
# Install the F5 NGINX Ingress Controller on AWS EKS using Helm.
# Values mirror the Terraform helm_release.nginx_ingress configuration in
# infrastructure/nginx-ingress.tf so both methods produce identical deployments.
#
# Chart  : nginx-stable/nginx-ingress  2.6.4
# App    : F5 NGINX Ingress Controller v5.5.4 (open-source)
# Repo   : https://helm.nginx.com/stable

set -euo pipefail

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update nginx-stable

helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
  --namespace nginx-ingress \
  --create-namespace \
  --version 2.6.4 \
  --wait \
  --timeout 10m \
  --atomic \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Cluster \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true" \
  --set controller.ingressClass.name=nginx \
  --set controller.ingressClass.create=true \
  --set controller.ingressClass.setAsDefaultIngress=false \
  --set controller.replicaCount=2 \
  --set prometheus.create=true \
  --set prometheus.port=9113 \
  --set prometheus.scheme=http

echo ""
echo "F5 NGINX Ingress Controller installed. NLB hostname:"
kubectl get svc nginx-ingress-controller -n nginx-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
