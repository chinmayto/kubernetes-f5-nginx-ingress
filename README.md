# kubernetes-f5-nginx-ingress

This repository demonstrates migrating from the deprecated community **ingress-nginx** controller to the **F5 NGINX Ingress Controller** on AWS EKS.

### Why F5 NGINX Ingress Controller instead of ingress-nginx?

The community `ingress-nginx` controller (maintained under `kubernetes/ingress-nginx`) has been deprecated. The F5 NGINX Ingress Controller is the actively maintained, enterprise-grade replacement backed by F5/NGINX Inc. Here's why the switch matters:

| | Community ingress-nginx | F5 NGINX Ingress Controller |
|---|---|---|
| **Status** | Deprecated | Actively maintained |
| **Maintainer** | Kubernetes community | F5 / NGINX Inc. |
| **Helm repo** | `kubernetes.github.io/ingress-nginx` | `helm.nginx.com/stable` |
| **Annotation prefix** | `nginx.ingress.kubernetes.io/` | `nginx.org/` |
| **Traffic splitting** | Canary annotations on Ingress | `VirtualServer` CRD with `splits` |
| **Basic auth** | `auth-type` / `auth-secret` annotations | `nginx.org/basic-auth-secret` |
| **SSL redirect** | `ssl-redirect` / `force-ssl-redirect` | `nginx.org/redirect-to-https` |
| **Advanced routing** | Annotation-only | `VirtualServer`, `VirtualServerRoute`, `TransportServer`, `Policy` CRDs |

The F5 NGINX Ingress Controller provides a richer, more explicit API via custom CRDs (`VirtualServer`, etc.) for traffic management that goes beyond what Kubernetes Ingress annotations can express, while remaining fully compatible with standard `networking.k8s.io/v1` Ingress resources for simpler use cases.

### Series

- [Part 1 – Installing F5 NGINX Ingress Controller on AWS EKS](./Part_01/README.md)
- [Part 2 – Routing with F5 NGINX Ingress Controller](./Part_02/README.md)
- [Part 3 – Basic Authentication with F5 NGINX Ingress Controller](./Part_03/README.md)
- [Part 4 – HTTPS with Self-Signed TLS Certificates](./Part_04/README.md)
- [Part 5 – HTTPS with Cert-Manager](./Part_05/README.md)
