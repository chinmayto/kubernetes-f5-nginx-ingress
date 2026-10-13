variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "CT-EKS-Cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster. Passed to the EKS module as `kubernetes_version`."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

####################################################################################
### DNS Variables
####################################################################################
variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
  default     = "chinmayto.com"
}

variable "app_subdomain" {
  description = "Subdomain for Node.js application (used by outputs for the primary app URL)"
  type        = string
  default     = "app"
}

variable "app_hostnames" {
  description = <<-EOT
    Fully-qualified hostnames to point at the NGINX Ingress NLB via Route 53
    alias A records. One record is created per entry. Use the apex domain
    (e.g. "chinmayto.com") and/or subdomains (e.g. "app1.chinmayto.com") to
    match the host(s) in the Ingress manifest(s) you deploy. Wildcard aliases
    (e.g. "*.chinmayto.com") are not supported by Route 53 for ELB/NLB targets.
  EOT
  type = list(string)
  # Matches the hosts used by the Ingress manifests in k8s-manifests/:
  #   app.chinmayto.com   -> basic routing and path-based routing (/app1, /app2)
  #   app1.chinmayto.com  -> host-based routing (app 1)
  #   app2.chinmayto.com  -> host-based routing (app 2)
  default = [
    "app.chinmayto.com",
    "app1.chinmayto.com",
    "app2.chinmayto.com",
  ]
}
