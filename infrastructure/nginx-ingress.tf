################################################################################
# Create F5 NGINX Ingress Controller namespace
################################################################################
resource "kubernetes_namespace_v1" "nginx_ingress" {
  metadata {
    name = "nginx-ingress"
    labels = {
      name = "nginx-ingress"
    }
  }

  depends_on = [module.eks]
}

resource "null_resource" "nginx_ingress" {
  triggers = {
    chart_version = "2.6.4"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]

    command = <<-EOT
      $ErrorActionPreference = "Stop"

      Write-Host "Installing F5 NGINX Ingress Controller..."

      helm upgrade --install nginx-ingress `
        oci://ghcr.io/nginx/charts/nginx-ingress `
        --version 2.6.4 `
        --namespace nginx-ingress `
        --create-namespace `
        --wait `
        --timeout 10m `
        --set controller.replicaCount=2 `
        --set controller.service.type=LoadBalancer `
        --set controller.service.externalTrafficPolicy=Local `
        --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=nlb' `
        --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme=internet-facing' `
        --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled=true' `
        --set controller.ingressClass.name=nginx `
        --set controller.ingressClass.create=true `
        --set controller.ingressClass.setAsDefaultIngress=false

      if ($LASTEXITCODE -ne 0) {
        throw "NGINX Ingress Helm installation failed"
      }

      Write-Host "NGINX Ingress installation completed."

      kubectl get pods -n nginx-ingress
      kubectl get svc -n nginx-ingress
      kubectl get ingressclass
    EOT
  }
}
################################################################################
# Retrieve the NLB hostname from the F5 NGINX Ingress Controller service.
#
# Service name "nginx-ingress-controller" is rendered by the chart when the
# Helm release name is "nginx-ingress" — confirmed via `helm template`.
#
# Uses kubernetes_service_v1 (not the deprecated kubernetes_service).
################################################################################
data "kubernetes_service_v1" "nginx_ingress_controller" {
  metadata {
    name      = "nginx-ingress-controller"
    namespace = kubernetes_namespace_v1.nginx_ingress.metadata[0].name
  }

  depends_on = [null_resource.nginx_ingress]
}

################################################################################
# Output the NLB hostname for use in Route 53 records or manual DNS setup.
################################################################################
output "nginx_ingress_nlb_hostname" {
  description = "Hostname of the NLB provisioned for the F5 NGINX Ingress Controller"
  value       = data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname
}
