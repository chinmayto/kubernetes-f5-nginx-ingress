helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update

helm upgrade -i nginx-ingress nginx-stable/nginx-ingress \
  --namespace nginx-ingress --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"