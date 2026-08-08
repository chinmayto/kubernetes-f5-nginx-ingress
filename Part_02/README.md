# Kubernetes Ingress Playlist – Part 2: Routing with F5 NGINX Ingress Controller

In the previous parts of the playlist, we learned what Ingress is and how to install the F5 NGINX Ingress Controller on AWS EKS.
Now in Part 2, we'll explore how routing works with practical examples using two simple Node.js applications:

`simple-nodejs-app-1`
`simple-nodejs-app-2`

Let's dive into the different types of routing supported by the F5 NGINX Ingress Controller.

> **Note on annotations:** All controller-specific annotations use the `nginx.org/` prefix. This is different from the community `ingress-nginx` controller which uses `nginx.ingress.kubernetes.io/`.

First, deploy both applications in separate deployments with a service:

Deploy first app:
```bash
kubectl apply -f https://raw.githubusercontent.com/chinmayto/kubernetes-f5-nginx-ingress/main/Part_03/deploy-simple-nodejs-app-1.yaml
```

Deploy second app:
```bash
kubectl apply -f https://raw.githubusercontent.com/chinmayto/kubernetes-f5-nginx-ingress/main/Part_03/deploy-simple-nodejs-app-2.yaml
```

Verify both apps are running. The first app exposes services to targetPort 8080 and the second at targetPort 8081.
```bash
$ kubectl get svc,pod -n simple-nodejs-app
NAME                           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/service-nodejs-app-1   ClusterIP   172.20.232.156   <none>        80/TCP    37s
service/service-nodejs-app-2   ClusterIP   172.20.80.39     <none>        80/TCP    26s

NAME                                           READY   STATUS    RESTARTS   AGE        
pod/deployment-nodejs-app-1-5cc7b94fd8-9dcsx   1/1     Running   0          38s        
pod/deployment-nodejs-app-1-5cc7b94fd8-zs477   1/1     Running   0          38s
pod/deployment-nodejs-app-2-7fc47d7995-9klmv   1/1     Running   0          26s
pod/deployment-nodejs-app-2-7fc47d7995-fc94w   1/1     Running   0          26s
```

The F5 NGINX Ingress Controller acts as a smart reverse proxy at the edge of the cluster, inspecting incoming requests and forwarding them based on predefined rules — by path, host, headers, or custom conditions. It consolidates access to multiple applications through a single IP address or load balancer and supports advanced traffic management strategies like TLS termination, traffic splitting, and authentication.

### 1) Basic Routing
Basic routing directs all incoming HTTP requests, regardless of path or host, to a single backend service. It's typically used when your cluster hosts one application or when you want all users to land on a common frontend.

Create a manifest file (nginx-ingress-basic-routing.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/rewrites: "serviceName=service-nodejs-app-1 rewrite=/"
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-1
                port:
                  number: 80
```

Apply it and see its details:
```bash
$ kubectl apply -f nginx-ingress-basic-routing.yaml 

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS   ADDRESS                                                                         PORTS   AGE
simple-nodejs-ingress   nginx   *       a602f172c106e4d4eb0736290c756d76-6d3fef0920a1c9a1.elb.us-east-1.amazonaws.com   80      57s
```

Access it using `http://<NLB-DNS>/`

![alt text](/Part_02/images/basic-routing.png)

### 2) Path-Based Routing
Path-based routing allows you to route traffic to different services based on the URL path. For example, requests to `/app1` can go to one service, while `/app2` goes to another. This is particularly useful in a microservices architecture.

Create a manifest file (nginx-ingress-path-based-routing.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/rewrites: "serviceName=service-nodejs-app-1 rewrite=/ serviceName=service-nodejs-app-2 rewrite=/"
spec:
  ingressClassName: nginx
  rules:
    - host: chinmayto.com
      http:
        paths:
          - path: /app1
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-1
                port:
                  number: 80
          - path: /app2
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-2
                port:
                  number: 80
```

Apply it and see its details:
```bash
$ kubectl apply -f nginx-ingress-path-based-routing.yaml 

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS           ADDRESS   PORTS   AGE
simple-nodejs-ingress   nginx   chinmayto.com             80      14s
```

Add an `A` record in Route 53 for `chinmayto.com` pointing to the NLB.

Access it using `http://chinmayto.com/app1` and `http://chinmayto.com/app2`

![alt text](/Part_02/images/path-routing-1.png)

![alt text](/Part_02/images/path-routing-2.png)

### 3) Host-Based Routing
Host-based routing makes routing decisions based on the HTTP `Host` header. It is ideal when you want to serve multiple applications using different domain names or subdomains — for example, `app1.example.com` routing to one app while `app2.example.com` points to another.

Create the manifest file (nginx-ingress-host-based-routing.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/rewrites: "serviceName=service-nodejs-app-1 rewrite=/ serviceName=service-nodejs-app-2 rewrite=/"
spec:
  ingressClassName: nginx
  rules:
    - host: app1.chinmayto.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-1
                port:
                  number: 80
    - host: app2.chinmayto.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-2
                port:
                  number: 80
```

Apply it and see its details:
```bash
$ kubectl apply -f nginx-ingress-host-based-routing.yaml 

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS                                   ADDRESS                                                                         PORTS   AGE
simple-nodejs-ingress   nginx   app1.chinmayto.com,app2.chinmayto.com   a602f172c106e4d4eb0736290c756d76-6d3fef0920a1c9a1.elb.us-east-1.amazonaws.com   80      9m52s
```

Add two `A` records in Route 53 for `app1.chinmayto.com` and `app2.chinmayto.com` pointing to the NLB.

Access it using `http://app1.chinmayto.com` and `http://app2.chinmayto.com`

![alt text](/Part_02/images/host-routing-1.png)

![alt text](/Part_02/images/host-routing-2.png)

### 4) Wildcard Routing
Wildcard routing matches multiple subdomains under a base domain using patterns like `*.example.com`. This is useful when serving dynamically generated subdomains without having to declare each one individually in the Ingress rules.

Create manifest file (nginx-ingress-wildcard-routing.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/rewrites: "serviceName=service-nodejs-app-1 rewrite=/"
spec:
  ingressClassName: nginx
  rules:
    - host: "*.chinmayto.com"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-nodejs-app-1
                port:
                  number: 80
```

Apply it and see its details:
```bash
$ kubectl apply -f nginx-ingress-wildcard-routing.yaml 

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS             ADDRESS   PORTS   AGE
simple-nodejs-ingress   nginx   *.chinmayto.com             80      7s
```

Add an `A` record in Route 53 for `*.chinmayto.com` pointing to the NLB.

Access it using `http://anything.chinmayto.com`

![alt text](/Part_02/images/wildcard-routing.png)

### 5) Regex-Based Routing
Regex-based routing adds pattern-matching capabilities by allowing regular expressions in path definitions. The F5 NGINX Ingress Controller supports this via `nginx.org/use-regex: "true"` and `pathType: ImplementationSpecific`.

Create manifest file (nginx-ingress-regex-based-routing.yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-nodejs-ingress
  namespace: simple-nodejs-app
  annotations:
    nginx.org/use-regex: "true"
    nginx.org/rewrites: "serviceName=service-nodejs-app-1 rewrite=/ serviceName=service-nodejs-app-2 rewrite=/"
spec:
  ingressClassName: nginx
  rules:
    - host: chinmayto.com
      http:
        paths:
          - path: /app1(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: service-nodejs-app-1
                port:
                  number: 80
          - path: /app2(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: service-nodejs-app-2
                port:
                  number: 80
```

Apply it and see its details:
```bash
$ kubectl apply -f nginx-ingress-regex-based-routing.yaml 

$ kubectl get ingress -n simple-nodejs-app
NAME                    CLASS   HOSTS           ADDRESS                                                                         PORTS   AGE
simple-nodejs-ingress   nginx   chinmayto.com   a602f172c106e4d4eb0736290c756d76-6d3fef0920a1c9a1.elb.us-east-1.amazonaws.com   80      7s
```

Add an `A` record in Route 53 for `chinmayto.com` pointing to the NLB.

Access it using `http://chinmayto.com/app1/anything`

![alt text](/Part_02/images/regex-routing.png)

### 6) Canary Routing
Canary routing enables progressive delivery by splitting a portion of traffic to a "canary" version of a service. The F5 NGINX Ingress Controller uses the **`VirtualServer` CRD** for traffic splitting — the annotation-based canary approach from community `ingress-nginx` is not supported. The `VirtualServer` resource defines both upstreams and the traffic split in a single manifest.

Create manifest (nginx-ingress-canary-based-canary-version.yaml) — this single `VirtualServer` resource replaces both the stable and canary Ingress objects:
```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: simple-nodejs-vs
  namespace: simple-nodejs-app
spec:
  ingressClassName: nginx
  host: chinmayto.com
  upstreams:
    - name: stable
      service: service-nodejs-app-1
      port: 80
    - name: canary
      service: service-nodejs-app-2
      port: 80
  routes:
    - path: /
      splits:
        - weight: 80
          action:
            pass: stable
        - weight: 20
          action:
            pass: canary
```

Apply it and see details:
```bash
$ kubectl apply -f nginx-ingress-canary-based-canary-version.yaml

$ kubectl get virtualserver -n simple-nodejs-app
NAME               STATE   HOST            IP    PORTS   AGE
simple-nodejs-vs   Valid   chinmayto.com                 10s
```

Add an `A` record in Route 53 for `chinmayto.com` pointing to the NLB.

Access `http://chinmayto.com` and refresh — roughly 80% of requests will hit app-1 (stable) and 20% will hit app-2 (canary).

### Conclusion
In this part, we explored the routing capabilities of the F5 NGINX Ingress Controller in Kubernetes. From basic routing to path-based, host-based, wildcard, regex, and canary routing, the F5 NGINX Ingress Controller offers fine-grained control over how traffic is directed to services inside your cluster.

A key difference from the community `ingress-nginx` controller is that canary/traffic-splitting uses the `VirtualServer` CRD with weighted `splits`, which is more expressive and explicit than annotation-based canary. All standard Ingress annotation keys use the `nginx.org/` prefix.

### References
- F5 NGINX Ingress Controller Docs: https://docs.nginx.com/nginx-ingress-controller/
- VirtualServer CRD reference: https://docs.nginx.com/nginx-ingress-controller/configuration/virtualserver-and-virtualserverroute-resources/
- GitHub Repo: https://github.com/chinmayto/kubernetes-f5-nginx-ingress/tree/main/Part_02
