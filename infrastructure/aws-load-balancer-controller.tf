################################################################################
# AWS Load Balancer Controller (LBC)
#
# Provisions AWS NLBs/ALBs from Kubernetes Service/Ingress objects. This is the
# modern replacement for the in-tree cloud-provider load balancer path.
#
# IAM access is granted via EKS Pod Identity (not IRSA). The cluster already
# runs the `eks-pod-identity-agent` addon (see main.tf), so no OIDC provider
# wiring is required. The official terraform-aws-modules/eks-pod-identity module
# creates the IAM role, attaches the maintained LBC IAM policy, and creates the
# Pod Identity association binding the role to the controller's ServiceAccount.
################################################################################

locals {
  lbc_namespace       = "kube-system"
  lbc_service_account = "aws-load-balancer-controller-sa"
}

################################################################################
# IAM role + LBC policy + Pod Identity association
################################################################################
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.cluster_name}-aws-lbc"

  # Attaches the AWS-maintained IAM policy for the Load Balancer Controller.
  attach_aws_lb_controller_policy = true

  association_defaults = {
    namespace       = local.lbc_namespace
    service_account = local.lbc_service_account
  }

  associations = {
    this = {
      cluster_name = module.eks.cluster_name
    }
  }

  tags = {
    Name      = "${var.cluster_name}-aws-lbc"
    Terraform = "true"
  }
}

################################################################################
# AWS Load Balancer Controller Helm release
#
# The ServiceAccount is created by the chart and must match the name bound in
# the Pod Identity association above. clusterName/region/vpcId are required so
# the controller can discover and tag the right AWS resources.
################################################################################
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.1" # chart 1.14.x ships controller app v2.17.x

  namespace        = local.lbc_namespace
  create_namespace = false # kube-system already exists

  wait    = true
  timeout = 600

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = module.vpc.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = local.lbc_service_account
    },
  ]

  depends_on = [
    module.eks,
    module.aws_lb_controller_pod_identity,
  ]

  # On destroy, null_resource.drain_nginx_service (defined in nginx-ingress.tf)
  # deletes the NGINX LoadBalancer Service and waits for its AWS LBC finalizer
  # to clear BEFORE this controller is uninstalled. Referencing it here via
  # lifecycle replace_triggered_by is not needed; the dependency edge is created
  # by drain_nginx_service.depends_on = [helm_release.aws_lb_controller], which
  # forces this release to be destroyed only after the drain completes.
}
