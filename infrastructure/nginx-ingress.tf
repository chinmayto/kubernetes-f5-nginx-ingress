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

################################################################################
# Install the F5 NGINX Ingress Controller via the native helm_release resource.
#
# This replaces the previous null_resource + local-exec `helm` invocation.
# Benefits over the imperative approach:
#   - Release is tracked in Terraform state (drift detection, clean upgrades).
#   - `terraform destroy` uninstalls the release in the correct order.
#   - No dependency on a local `helm` binary or PowerShell at apply time.
#   - Chart version changes are a normal plan/apply, not a trigger hack.
################################################################################
resource "helm_release" "nginx_ingress" {
  name = "nginx-ingress"

  # Install from the locally vendored copy of the chart (originally
  # oci://ghcr.io/nginx/charts/nginx-ingress v2.6.4) rather than directly from
  # the OCI registry. The vendored copy's values.schema.json has been replaced
  # with a permissive schema because the upstream schema contains hard-coded
  # $ref URLs to nginxinc/kubernetes-json-schema for the cluster's Kubernetes
  # version (e.g. v1.36.1), which do not exist and make Helm fail with
  # "values don't meet the specifications of the schema". There is no
  # helm_release flag to skip chart values-schema validation, so neutralizing
  # the bundled schema is the reliable fix. The original schema is preserved at
  # nginx-ingress/values.schema.json.bak.
  chart = "${path.module}/nginx-ingress"

  namespace        = kubernetes_namespace_v1.nginx_ingress.metadata[0].name
  create_namespace = false # namespace is managed by kubernetes_namespace_v1 above

  # Wait for the chart's resources (incl. the Service) to be ready before the
  # resource is considered created. Note: this waits for the Service object,
  # not for the AWS NLB hostname to be assigned — that is handled below.
  wait    = true
  timeout = 600 # seconds (10m)

  # Plain controller settings, plus the AWS load balancer service annotations.
  #
  # These annotations target the AWS Load Balancer Controller (installed in
  # aws-load-balancer-controller.tf), not the legacy in-tree cloud provider:
  #   aws-load-balancer-type: "external"      -> hand provisioning to the LBC
  #   aws-load-balancer-nlb-target-type: "ip" -> register pod IPs directly
  #   aws-load-balancer-scheme: "internet-facing"
  #
  # Values are forced to type "string" so Helm does not coerce them, and the
  # dots in the annotation keys are escaped so Helm treats each annotation name
  # as a single key segment.
  set = [
    {
      name  = "controller.replicaCount"
      value = "2"
    },
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      # With NLB "ip" target mode the LB sends traffic straight to pod IPs
      # (no nodePort hop), so the client IP is preserved natively. Use
      # "Cluster" here — "Local" is for "instance" target type and causes
      # NLB health-check failures with ip targets.
      name  = "controller.service.externalTrafficPolicy"
      value = "Cluster"
    },
    {
      name  = "controller.ingressClass.name"
      value = "nginx"
    },
    {
      name  = "controller.ingressClass.create"
      value = "true"
    },
    {
      name  = "controller.ingressClass.setAsDefaultIngress"
      value = "false"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "external"
      type  = "string"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
      value = "ip"
      type  = "string"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
      type  = "string"
    },
  ]

  # The AWS Load Balancer Controller must be running before the NGINX Service
  # is created, otherwise there is nothing to reconcile the NLB for the Service.
  depends_on = [
    module.eks,
    helm_release.aws_lb_controller,
  ]
}

################################################################################
# Destroy-time drain of the NGINX LoadBalancer Service.
#
# The NGINX controller Service carries the AWS Load Balancer Controller
# finalizer "service.k8s.aws/resources". On destroy, Terraform uninstalling the
# NGINX Helm release deletes the Service object, but the finalizer is cleared
# asynchronously by the LBC as it deprovisions the NLB. If the LBC is torn down
# first, that finalizer never clears, the Service hangs in Terminating, and the
# nginx-ingress namespace is stuck forever.
#
# This resource forces the correct ordering: because helm_release.aws_lb_controller
# depends on it, Terraform runs this destroy-time provisioner (which deletes the
# Service and waits for it to fully disappear) BEFORE uninstalling the LBC. The
# LBC is therefore still alive to process the finalizer and delete the NLB.
################################################################################
resource "null_resource" "drain_nginx_service" {
  triggers = {
    namespace = kubernetes_namespace_v1.nginx_ingress.metadata[0].name
  }

  # Destroy-time only. Deletes the NGINX LoadBalancer Service and blocks until
  # Kubernetes has fully removed it (finalizer processed by the LBC).
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-Command"]

    command = <<-EOT
      $ErrorActionPreference = "SilentlyContinue"

      Write-Host "Draining NGINX LoadBalancer Service before removing the AWS Load Balancer Controller..."

      # Trigger deletion (ignore if it is already gone).
      kubectl delete svc nginx-ingress-controller -n nginx-ingress --ignore-not-found --wait=$false | Out-Null

      $maxAttempts = 60   # 60 x 10s = up to 10 minutes
      for ($i = 1; $i -le $maxAttempts; $i++) {
        kubectl get svc nginx-ingress-controller -n nginx-ingress 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
          Write-Host "NGINX LoadBalancer Service is gone (NLB deprovisioned by the LBC)."
          exit 0
        }
        Write-Host "Attempt $i/$maxAttempts - service still terminating, waiting 10s..."
        Start-Sleep -Seconds 10
      }

      Write-Host "WARNING: timed out waiting for the NGINX Service to delete; continuing."
      exit 0
    EOT
  }

  depends_on = [
    helm_release.aws_lb_controller,
    helm_release.nginx_ingress,
  ]
}

################################################################################
# Wait until the AWS NLB hostname is populated on the Service status.
#
# helm_release's `wait` returns once the Service object exists, but the external
# load balancer hostname is assigned asynchronously by the AWS cloud controller
# and may not be present yet. The data source below reads
# status.loadBalancer.ingress[0].hostname, so we block here until it exists to
# avoid an index-out-of-range on a cold apply.
################################################################################
resource "null_resource" "wait_for_nlb_hostname" {
  triggers = {
    release_revision = helm_release.nginx_ingress.metadata.revision
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]

    command = <<-EOT
      $ErrorActionPreference = "Stop"

      Write-Host "Waiting for NLB hostname to be assigned to the ingress service..."

      $hostname = ""
      $maxAttempts = 60   # 60 attempts x 10s = up to 10 minutes
      for ($i = 1; $i -le $maxAttempts; $i++) {
        $hostname = kubectl get svc nginx-ingress-controller `
          -n nginx-ingress `
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null

        if (-not [string]::IsNullOrEmpty($hostname)) {
          Write-Host "NLB hostname assigned: $hostname"
          break
        }

        Write-Host "Attempt $i/$maxAttempts - hostname not ready yet, retrying in 10s..."
        Start-Sleep -Seconds 10
      }

      if ([string]::IsNullOrEmpty($hostname)) {
        throw "Timed out waiting for the NLB hostname on service/nginx-ingress-controller"
      }
    EOT
  }

  depends_on = [helm_release.nginx_ingress]
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

  depends_on = [null_resource.wait_for_nlb_hostname]
}

################################################################################
# Output the NLB hostname for use in Route 53 records or manual DNS setup.
################################################################################
output "nginx_ingress_nlb_hostname" {
  description = "Hostname of the NLB provisioned for the F5 NGINX Ingress Controller"
  value       = data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname
}
