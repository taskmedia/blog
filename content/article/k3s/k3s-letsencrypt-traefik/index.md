---
title: "Setup k3s with LetsEncrypt and Traefik dashboard exposed"
date: 2022-02-16T12:00:00+01:00

tags:
  [
    "k3s",
    "k8s",
    "kubernetes",
    "traefik",
    "dashboard",
    "reverseproxy",
    "proxy",
    "ingress",
    "ingressroute",
  ]
author: "Marco"
---

# About

This article describes how to expose a Kubernetes instance running with [k3s](https://k3s.io/) with TLS certificates from [Let’s Encrypt](https://letsencrypt.org/).

The K3s installation will install a Traefik ingress on its default configuration.
But it will not have a certificate resolver present and uses the Traefik default certificate.

# Versions

- K3s: `v1.22.6+k3s1 (3228d9cb)`
- K8s-Client: `1.23.3`
- K8s-Server: `1.22.6+k3s1`
- Traefik: `2.6.1`
- Traefik Helmchart: `10.9.100`

# Installation k3s

The installation of k3s is quite simple.
We are following the [installation guide](https://rancher.com/docs/k3s/latest/en/installation/install-options/#options-for-installation-with-script) of k3s documentation on rancher.com.

```bash
# Set hostname as node name
$ export K3S_NODE_NAME=$(hostname -f)

# start installation
$ curl -sfL https://get.k3s.io | sh -
```

After the installation the Kubernetes configuration file of ranger can be copied from k3s.

```bash
$ cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
```

# Configure k3s Traefik ingress

To use the preinstalled ingress with certificates you need to add some additional configuration to your Traefik.
You will find the deployment [Helm](https://helm.sh/) configuration here: `/var/lib/rancher/k3s/server/manifests/traefik.yaml`.
Keep in mind not to change this configuration file because it might be overwritten by k3s later (e.g. on upgrade).

To configure the k3s ingress correctly please create a HelmChartConfig resources as described in the official [documentation](https://rancher.com/docs/k3s/latest/en/helm/#customizing-packaged-components-with-helmchartconfig).
This section will guide you through this simple configuration.

We will add the following parameters:

- traefik image and tag _(default uses a [mirrored image](https://github.com/k3s-io/k3s/blob/a094dee7dd0d7e7f7b2c8d50f90bb6760f9c86bf/manifests/traefik.yaml#L34-L35))_
- enable [insecure API](https://doc.traefik.io/traefik/operations/api/#insecure) mode
- add [certificate resolvers](https://doc.traefik.io/traefik/https/acme/#using-letsencrypt-with-kubernetes) (Let's Encrypt staging and prod)

The configuration will be added to the Helm chart by overwriting the values file.
You will find all possible configuration options in the complete [values.yaml](https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml) file of the chart.

The image will be specified directly as `image.name` and `image.tag`.
All other configurations mentioned above will be specified as arguments to Traefik.
Therefore we use `globalArguments`.

In order to keep already given configurations from k3s we copy the valuesContent from the k3s traefik manifest.
This file can be found on the mentioned path above on your server (`/var/lib/rancher/k3s/server/manifests/traefik.yaml`) or have a look on [GitHub](https://github.com/k3s-io/k3s/blob/master/manifests/traefik.yaml).

I added my custom configuration on top of the copied on from the existing manifest (separated by a comment).

Place the configuration at `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml`.

## Modified Traefik configuration

```yaml
# traefik-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      name: traefik
      tag: v2.6.1

    globalArguments:
      - "--global.checknewversion=false"
      - "--global.sendanonymoususage=false"
      - "--api.insecure=true"
      - "--certificatesresolvers.le-staging.acme.tlschallenge"
      - "--certificatesresolvers.le-staging.acme.email=mail@task.media"
      - "--certificatesresolvers.le-staging.acme.storage=acme.json"
      - "--certificatesresolvers.le-staging.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
      - "--certificatesresolvers.le-staging.acme.storage=/data/acme.json"
      - "--certificatesresolvers.le-prod.acme.tlschallenge"
      - "--certificatesresolvers.le-prod.acme.email=mail@task.media"
      - "--certificatesresolvers.le-prod.acme.storage=acme.json"
      - "--certificatesresolvers.le-prod.acme.caserver=https://acme-v02.api.letsencrypt.org/directory"
      - "--certificatesresolvers.le-prod.acme.storage=/data/acme.json"

    # ---- k3s Traefik default configuration below ----
    rbac:
      enabled: true
    ports:
      websecure:
        tls:
          enabled: true
    podAnnotations:
      prometheus.io/port: "8082"
      prometheus.io/scrape: "true"
    providers:
      kubernetesIngress:
        publishedService:
          enabled: true
    priorityClassName: "system-cluster-critical"
    tolerations:
    - key: "CriticalAddonsOnly"
      operator: "Exists"
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
    - key: "node-role.kubernetes.io/master"
      operator: "Exists"
      effect: "NoSchedule"
```

Important is also to remove duplicate entries - e.g. on the default k3s configuration I had to remove `image.name`.
Otherwise your changes will not be reflected.

## Deployment modified Traefik ingress

To deploy the modified ingress you do not need to deploy the yaml-file yourself.
K3s will keep track of the directory where the file was placed and run Helm to deploy changes.

To verify if the changes are inherited have a look at the pods in namespace `kube-system`:

```bash
$ kubectl get pod -n kube-system
NAME                                      READY   STATUS      RESTARTS   AGE
local-path-provisioner-84bb864455-hzk75   1/1     Running     0          12h
coredns-96cc4f57d-cg59b                   1/1     Running     0          12h
helm-install-traefik-crd--1-24p6k         0/1     Completed   0          12h
metrics-server-ff9dbcb6c-bwcv2            1/1     Running     0          12h
svclb-traefik-2qxsw                       2/2     Running     0          12h
helm-install-traefik--1-pw4cs             0/1     Completed   1          2m4s
traefik-968cf9598-6qxtm                   1/1     Running     0          2m1s
```

You can see the `helm-install-traefik-*` pod was completed 2 minutes ago.
This pod deployed the changes from the added HelmChartConfig.

This resulted in a updated `traefik-*` pod with updated configuration.
To check the configuration you can view the pod: `kubectl get pod traefik-968cf9598-6qxtm -o yaml` and search for e.g. the args of the container or the used image.

# Expose Traefik dashboard

To check your configuration we now will expose the Traefik dashboard.
Keep in mind that it is not recommended to publish the Traefik dashboard to the public (especially not unprotected).

We will use the [Custom Resource](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) [IngressRoute](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-ingressroute) (CRD from Traefik) to expose the dashboard to a public domain.

```yaml
# ingress-traefik-dashboard-public.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard-public
  namespace: kube-system
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`traefik.example.org`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    # use staging certificates
    # keep in mind you will get a TLS warning by your browser when using staging!
    certResolver: le-staging
```

This file should not be saved in the same location as the `traefik-config.yml`.
Replace `traefik.example.org` with your domain.

To deploy this IngressRoute apply the configuration with following command:

```bash
kubectl apply -f ./ingress-traefik-dashboard-public.yaml
```

After a successful deployment the traefik dashboard should be exposed at the defined domain:

```
https://traefik.example.org/dashboard/
```

As described in the yaml the certificate will not be trusted by your browser because currently the Let's Encrypt staging resolver is used.
This occurs in a `Your connection is not private: ERR_CERT_AUTHORITY_INVALID` error on your browser.
To change the certificate to a trusted on change the the resolver to `spec.tls.certResolver: le-prod`.
