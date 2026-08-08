# Kubernetes Ingress Playlist – Part 5: Securing the Kubernetes Ingress Using Cert-Manager with HTTPS

In the previous parts of our Kubernetes Ingress playlist, we covered installing the F5 NGINX Ingress Controller, implementing host/path-based routing, enabling authentication, and adding self-signed TLS. Now, it's time to automate certificate management using **Cert-Manager** — a powerful tool that simplifies issuing and renewing SSL/TLS certificates within your Kubernetes cluster.

In this part, we'll:

1. Deploy the `simple-nodejs-app`
2. Install and configure Cert-Manager
3. Automatically issue TLS certificates via Let's Encrypt using a `ClusterIssuer`
4. Secure our F5 NGINX Ingress endpoint with HTTPS

### What is Cert-Manager?
Cert-Manager is a native Kubernetes certificate management controller that automates the issuance, renewal, and use of TLS certificates. It supports multiple certificate issuers such as:
1. Let's Encrypt (ACME)
2. HashiCorp Vault
3. Self-signed certificates
4. Venafi, and more

With Cert-Manager, you don't need to manually generate and rotate certificates. It integrates seamlessly with Kubernetes and works great with Ingress resources.

###  Step 1: Install Cert-Manager using Helm

We will use Helm to install Cert-Manager. The following commands install the controller and its required CustomResourceDefinitions (CRDs).

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.3 \
  --set installCRDs=true
```

Output:
```bash
NAME: cert-manager
LAST DEPLOYED: Wed Aug  6 00:16:00 2025
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager v1.14.3 has been deployed successfully!
```

Verify the installation:
```bash
$ kubectl get pods --namespace cert-manager
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-6c4645d66c-vlrd7              1/1     Running   0          4m23s
cert-manager-cainjector-55c5b94bfc-mnhln   1/1     Running   0          4m23s
cert-manager-webhook-549d7475d7-f9rzw      1/1     Running   0          4m23s
```

### Step 2: Create a ClusterIssuer for Let's Encrypt

Cert-Manager needs an Issuer to request certificates from a Certificate Authority like Let's Encrypt. A `ClusterIssuer` is cluster-wide (not namespace-scoped).

> **Important:** When using the F5 NGINX Ingress Controller, the HTTP-01 solver must reference the ingress class using `ingressClassName` instead of the deprecated `class` field.

Create manifest (cluster_issuer.yaml):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-nginx-cert
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: newabog237@misehub.com
    privateKeySecretRef:
      name: letsencrypt-nginx-cert
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

Apply it and verify:
```bash
$ kubectl apply -f cluster_issuer.yaml 
clusterissuer.cert-manager.io/letsencrypt-nginx-cert created

$ kubectl get clusterissuer letsencrypt-nginx-cert
NAME                     READY   AGE
letsencrypt-nginx-cert   True    4m20s
```

### Step 3: Create a TLS-enabled Ingress

The F5 NGINX Ingress Controller uses `nginx.org/redirect-to-https: "true"` for HTTPS enforcement. This replaces both `nginx.ingress.kubernetes.io/ssl-redirect` and `nginx.ingress.kubernetes.io/force-ssl-redirect` from the community controller. Cert-Manager will automatically provision a TLS certificate and store it in the `simple-nodejs-tls-secret` secret.

Create manifest file (nginx-ingress-with-cert-manager.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-nginx-cert"
    nginx.org/redirect-to-https: "true"
    nginx.org/rewrites: "serviceName=service-nodejs-app rewrite=/"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - chinmayto.com
      secretName: simple-nodejs-tls-secret
  rules:
    - host: chinmayto.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app
                port:
                  number: 80
```

Apply and verify:
```bash
$ kubectl apply -f nginx-ingress-with-cert-manager.yaml 
ingress.networking.k8s.io/simple-nodejs-ingress created

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS           ADDRESS                                                                         PORTS     AGE
simple-nodejs-ingress   nginx   chinmayto.com   a4374e0452f8c4e0c99602307d9cb013-4fe3550df37ae3d7.elb.us-east-1.amazonaws.com   80, 443   43s

$ kubectl get secret -n simple-nodejs-app
NAME                       TYPE                DATA   AGE
simple-nodejs-tls-secret   kubernetes.io/tls   2      23s
```

This will also create a Certificate resource. Describe it to get the event log:
```bash
$ kubectl get certificate -n simple-nodejs-app
NAME                       READY   SECRET                     AGE
simple-nodejs-tls-secret   True    simple-nodejs-tls-secret   64s

$ kubectl describe certificate -n simple-nodejs-app
Name:         simple-nodejs-tls-secret
Namespace:    simple-nodejs-app
...
Status:
  Conditions:
    Message:               Certificate is up to date and has not expired
    Reason:                Ready
    Status:                True
    Type:                  Ready
Events:
  Type    Reason     Age    From                                       Message
  ----    ------     ----   ----                                       -------
  Normal  Issuing    3m26s  cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  3m25s  cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource
  Normal  Requested  3m25s  cert-manager-certificates-request-manager  Created new CertificateRequest resource
  Normal  Issuing    3m3s   cert-manager-certificates-issuing          The certificate has been successfully issued
```

### Annotation Reference

| Community ingress-nginx | F5 NGINX Ingress Controller |
|---|---|
| `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | `nginx.org/redirect-to-https: "true"` |
| `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` | `nginx.org/redirect-to-https: "true"` _(same annotation covers both)_ |
| `nginx.ingress.kubernetes.io/rewrite-target: /` | `nginx.org/rewrites: "serviceName=... rewrite=/"` |
| ClusterIssuer solver `class: nginx` | ClusterIssuer solver `ingressClassName: nginx` |

Now access `https://chinmayto.com` in your browser. The certificate should be signed by Let's Encrypt. Even accessing `http://chinmayto.com` will redirect to HTTPS.

![alt text](/Part_05/images/secure-website.png)

![alt text](/Part_05/images/valid-cert.png)

> **Note:** If the certificate status is not `READY`, describe the `CertificateRequest` and `Challenge` resources to troubleshoot:
> ```bash
> kubectl describe challengs -n simple-nodejs-app
> ```

### Conclusion
Using Cert-Manager with the F5 NGINX Ingress Controller, we've automated the entire TLS certificate lifecycle within our Kubernetes cluster. Instead of relying on self-signed certs or manual renewals, Cert-Manager:

1. Automatically provisions and renews certificates
2. Integrates with Ingress resources for seamless HTTPS
3. Supports both staging and production Let's Encrypt issuers

The key changes from the community controller are the updated annotation prefixes (`nginx.org/` instead of `nginx.ingress.kubernetes.io/`) and the use of `ingressClassName` instead of `class` in the ClusterIssuer solver. Everything else — the Cert-Manager setup, ClusterIssuer, and TLS secret — works identically.

### References
1. F5 NGINX Ingress Controller Docs: https://docs.nginx.com/nginx-ingress-controller/
2. Cert-Manager Docs: https://cert-manager.io/docs/
3. GitHub Repo: https://github.com/chinmayto/kubernetes-f5-nginx-ingress/tree/main/Part_05
