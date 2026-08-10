# Kubernetes Ingress Playlist – Part 3: Basic Authentication with F5 NGINX Ingress Controller

In the previous parts of this playlist, we explored what Ingress is, installed the F5 NGINX Ingress Controller on AWS EKS, and configured routing rules. In this part, we'll focus on securing access to our application using Basic Authentication.

We'll use the same `simple-nodejs-app` deployed on EKS as the backend service.

### Step 0: Deploy the Node.js App

```bash
kubectl apply -f deploy-simple-nodejs-app.yaml
```

The manifest creates a Namespace, Deployment (2 replicas), and ClusterIP Service:
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: simple-nodejs-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: simple-nodejs-app
  name: deployment-nodejs-app
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: nodejs-app
  replicas: 2
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nodejs-app
    spec:
      containers:
      - image: public.ecr.aws/n4o6g6h8/simple-nodejs-app:latest
        imagePullPolicy: Always
        name: nodejs-app
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  namespace: simple-nodejs-app
  name: service-nodejs-app
spec:
  type: ClusterIP
  ports:
    - port: 80
      name: http
      targetPort: 8080
  selector:
    app.kubernetes.io/name: nodejs-app
```

### What is Basic Authentication?
Basic Authentication is a simple authentication mechanism where a client provides a username and password with each HTTP request. While not the most secure form of authentication (especially without HTTPS), it's quick and useful for internal applications or early-stage deployments.

### Prerequisites
1. A working Kubernetes cluster with the F5 NGINX Ingress Controller installed (we're using AWS EKS).
2. `kubectl` configured to access your cluster.
3. `htpasswd` utility installed locally (available via `apache2-utils` or `httpd-tools`).

### Step 1: Create a Password File using htpasswd
Generate a password file using the `htpasswd` command:

```bash
htpasswd -c auth adminuser
```

You'll be prompted to enter a password. This creates a file called `auth` with credentials for user `adminuser`.

### Step 2: Create a Kubernetes Secret with the Credentials
Create a Kubernetes secret from the generated htpasswd file:

```bash
kubectl create secret generic basic-auth --from-file=auth -n simple-nodejs-app
```

This creates a secret named `basic-auth` in the `simple-nodejs-app` namespace.

### Step 3: Create an Ingress Resource with Basic Auth Annotations

The F5 NGINX Ingress Controller uses `nginx.org/basic-auth-secret` and `nginx.org/basic-auth-realm` annotations for basic authentication. These replace the `nginx.ingress.kubernetes.io/auth-type`, `auth-secret`, and `auth-realm` annotations used by the community controller.

Create manifest file (nginx-ingress-basic-auth.yaml):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/rewrites: "serviceName=service-nodejs-app rewrite=/"
    # Basic authentication using F5 NGINX Ingress Controller annotations
    nginx.org/basic-auth-secret: "basic-auth"
    nginx.org/basic-auth-realm: "Authentication Required"
spec:
  ingressClassName: nginx
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

Make sure host `chinmayto.com` points to your Ingress controller's external IP (via `/etc/hosts` or a Route 53 record).

Apply it using:
```bash
kubectl apply -f nginx-ingress-basic-auth.yaml
```

Access it using the host name `http://chinmayto.com`

![alt text](/Part_03/images/basic_auth.png)

![alt text](/Part_03/images/auth_success.png)

### Annotation Reference

| Community ingress-nginx | F5 NGINX Ingress Controller |
|---|---|
| `nginx.ingress.kubernetes.io/auth-type: "basic"` | _(implicit — secret format determines type)_ |
| `nginx.ingress.kubernetes.io/auth-secret: "basic-auth"` | `nginx.org/basic-auth-secret: "basic-auth"` |
| `nginx.ingress.kubernetes.io/auth-realm: "..."` | `nginx.org/basic-auth-realm: "..."` |

### Conclusion
In this part of the Kubernetes Ingress playlist, we explored how to secure access to applications using Basic Authentication with the F5 NGINX Ingress Controller. The `nginx.org/basic-auth-secret` and `nginx.org/basic-auth-realm` annotations provide a straightforward mechanism to restrict access by requiring a valid username and password before users can reach your application.

This method is especially useful for quickly protecting internal tools, development environments, or staging applications without setting up a full-fledged authentication system. While it should not be considered a comprehensive security measure — especially without HTTPS — it serves as a simple and effective first layer of protection.

### References
1. F5 NGINX Ingress Controller — Basic Auth: https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/advanced-configuration-with-annotations/
2. GitHub Repo: https://github.com/chinmayto/kubernetes-f5-nginx-ingress/tree/main/Part_03
