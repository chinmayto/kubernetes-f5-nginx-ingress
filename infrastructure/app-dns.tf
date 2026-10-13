####################################################################################
### Route53 DNS Records for Node.js App (pointing to NGINX Ingress NLB)
###
### One alias A record is created per hostname in var.app_hostnames, matching
### the hosts used by the Ingress manifests in k8s-manifests/:
###   app.chinmayto.com   -> basic routing and path-based routing (/app1, /app2)
###   app1.chinmayto.com  -> host-based routing (app 1)
###   app2.chinmayto.com  -> host-based routing (app 2)
####################################################################################
resource "aws_route53_record" "nodejs_app" {
  for_each = toset(var.app_hostnames)

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = "Z26RNL4JYFTOTI" # NLB hosted zone ID for us-east-1
    evaluate_target_health = true
  }

}
