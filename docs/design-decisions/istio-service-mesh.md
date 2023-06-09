# Istio Service Mesh configuration, gotchas, canary deployments

**Author:** Marshall Bentley
**Date:** 11/01/2022

## Context and Scope

In order to implement traffic management features such as canary and a / b deployments, the Network Observability control-plane plans to leverage a Service Mesh.  A service mesh is a dedicated infrastructure layer that you can add to your applications. It allows you to transparently add capabilities like observability, traffic management, and security, without adding them to your own code.  Due to its large number of features and widespread industry adoption, we have chosen Istio as our service mesh implementation.

This document is intended to be an overview of the configuration applied in the control-plane, configuration gotchas and a review of deploying applications to the control-plane in a canary deployment configuration.

## Istio Overview

[Istio](https://istio.io/latest/) is an open-source implementation of a [Service Mesh](https://istio.io/latest/about/service-mesh/) architecture.  It has a large feature set, widespread industry adoption and is well documented.  Istio leverages [Envoy](https://www.envoyproxy.io/), a graduated CNCF project as its service proxy.  The Network Observability control-plane includes Istio as a dial tone service.

## Istio Features

At a high level, Istio provides the following features:

- Traffic Management
  - Canary deployments
  - A / B deployments
  - Traffic mirroring
- Resilience
  - Request timeouts
  - Request retries
  - Health based circuit breakers
  - Chaos engineering (intentionally adding errors / delays for testing purposes)
- Security
  - Encryption between pods (mTLS)
  - Authentication
  - Authorization
  - Integrity
- Observability
  - Metrics
  - Logging
  - Distributed tracing
  - Dashboards / visualizations

### Istio Installation

Istio offers several methods of installation including a dedicated CLI ([istioctl](https://istio.io/latest/docs/reference/commands/istioctl/)).  To align with GitOps principals and the Coral architecture, we have chosen to install via Helm for the Network Observability control-plane.  Our installation uses a Coral ManifestDeployment with the following folder structure:

```yaml
applications/coral-system/ManifestDeployments/
├── istio.yaml

manifests/istio/
├── istio-base-release.yaml
├── istiod-release.yaml
├── kustomization.yaml
├── patches
│   ├── istio-base-config.yaml
│   └── istiod-config.yaml
└── repository.yaml

manifests/namespaces/
├── kustomization.yaml
└── namespace.yaml
```

The installation consists of two charts, [base](https://github.com/istio/istio/tree/master/manifests/charts/base) and [istiod](https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery).  Each chart has its own HelmRelease `manifests/istio/istio-base-release.yaml` and `manifests/istio/istiod-release.yaml`.

Configuration is applied to these charts via the Coral patches `manifests/istio/patches/istio-base-config.yaml` and `manifests/istio/patches/istiod-config.yaml`

## Istio Configuration

### Istio Component Installation

For ease of administration, Istio has been configured to install its CRDs / components in the `infrastructure` namespace instead of the default `istio-system` namespace using the following configuration:

```yaml
spec:
  values:
    global:
      istioNamespace: infrastructure
```

#### Envoy Proxy Injection

Istio installs an Envoy proxy into each pod and routes communication through it.  This installation is automated and is controlled using Kubernetes labels.  Labeling a namespace with `istio-injection=enabled` causes Istio to automatically inject Envoy sidecars into each pod in that namespace.

For the Network Observability control-plane, we have configured the `infrastructure` namespace this way using the following configuration in `manifests/namespaces/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    istio-injection: enabled
  name: infrastructure
```

When Istio installs Envoy into a pod, it applies labels and annotations to it to setup routing through the proxy and expose ports and metadata.  It automatically handles converting any labels and annotations existing on the pod before installation into the metadata it exposes in order to preserve functionality.

## Prometheus Monitoring

The Network Observability control-plane uses Kubernetes `prometheus.io` annotations to configure Prometheus monitoring of applications and services.  When Prometheus sees pods with these annotations, it monitors them for metrics.

Istio preserves the functionality to configure monitoring using these annotations.  If the annotations already exist when Istio injects the Envoy sidecar, it configures Envoy to merge metrics published by the application with those published by Istio and overwrites the annotations to expose metrics to be scraped at `:15020/stats/prometheus`.

Istio also publishes [its own metrics](https://istio.io/latest/docs/reference/config/metrics/) to Prometheus by default.

## Grafana Dashboards

Istio provides several preconfigured [Grafana dashboards](https://istio.io/latest/docs/ops/integrations/grafana/) to view the status of the Service Mesh based on its metrics:

- [Mesh Dashboard](https://grafana.com/grafana/dashboards/7639): provides an overview of all services in the mesh.
- [Service Dashboard](https://grafana.com/grafana/dashboards/7636): provides a detailed breakdown of metrics for a service.
- [Workload Dashboard](https://grafana.com/grafana/dashboards/7630): provides a detailed breakdown of metrics for a workload.
- [Performance Dashboard](https://grafana.com/grafana/dashboards/11829): monitors the resource usage of the mesh.
- [Control Plane Dashboard](https://grafana.com/grafana/dashboards/7645): monitors the health and performance of the control plane.

The Network Observability control-plane includes these dashboards and they are ready for use at startup.

## Centralized Logging

The Network Observability control-plane includes centralized logging leveraging Fluentbit, Elasticsearch and Kibana.  All logs, including Istio's, are forwarded to Elasticsearch where they can be visualized using Kibana.

## Kiali

[Kiali](https://kiali.io/) is an observability console for Istio with service mesh configuration and validation capabilities. It helps you understand the structure and health of your service mesh by monitoring traffic flow to infer the topology and report errors.

The Network Observability control-plane includes Kiali and deploys it using a dedicated ManifestDeployment / HelmRelease using the following configuration:

```yaml
spec:
  values:
    metrics:
      enabled: true
    cr:
      create: true
      namespace: "infrastructure"
      spec:
        auth:
          strategy: "anonymous"
        external_services:
          istio:
            root_namespace: "infrastructure"
          prometheus:
            url: "http://prometheus-server.infrastructure.svc.cluster.local"
```

## Istio Certificate Management

More information on Istio certificate management can be found in the main [certificate management docs](./certificate-management.md)

## Accessing Cluster Resources With Istio Gateway

This control plane provides external access to cluster resources via an Istio Gateway.  Routing external traffic through a Gateway secure https / TLS communication to be enforced and allows Istio routing rules to be applied.  It's important that users use the Gateway to access cluster resources externally and don't use port forwarding as Istio routing rules are not applied to port forwarded connections.

After deployment, use the following command to determine the external Gateway address:

```bash
kubectl get service -A | grep istio-gateway
NAME                                             TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                                                                        AGE
istio-gateway                                    LoadBalancer   10.0.91.80     13.77.224.85   15021:31967/TCP,8080:30912/TCP,5601:32085/TCP,20001:31033/TCP,9411:31851/TCP   21h
```

After obtaining the Gateway's external address, the following services are available on the described ports:

- Grafana: Port 8080
- Kibana: Port 5601
- Kiali: Port 20001
- Zipkin: Port 9411

All communication through the Gateway must use https.  Services are exposed using the following URL format:

```bash
https://<external gateway address>:<service port number>
```

For example, to access Grafana using these values we would use:

```bash
https://13.77.224.85:8080
```

## Istio Gotchas

### Istio Routing Not Applied to Ingress Gateway Requests

Istio does not apply routing rules configured for services inside the mesh to requests entering the mesh through an ingress gateway.  In order to apply routing rules to these requests, they must be configured on `VirtualService` objects that are directly applied to the gateway.

For example, let's say you have two versions of an app running in a cluster, `app-v1` and `app-v2` as well as a service which forwards traffic to both.  By default, with no rules applied, Istio will distribute traffic in a round robin fashion to both versions in a 50 / 50 split.  Let's now say you configure a `VirtualService` to send all traffic to `app-v2`.  What will actually happen is requests originating from services within the cluster will respect the `VirtualService` rule and all requests will be routed to `app-v2`.  However, requests originating from an ingress gateway will NOT respect the `VirtualService` rule and traffic will instead have the default behavior applied which results in traffic being routed in a 50 / 50 split.  This happens because the `VirtualService` rule is applied to the service and not directly the gateway.  In order for the rule to apply to requests originating from the ingress gateway, the `VirtualService` needs to be directly applied to the gateway.

More info can be found here: <https://istio.io/latest/docs/ops/common-problems/network-issues/#route-rules-have-no-effect-on-ingress-gateway-requests>

### Istio Routing Not Applied Over Port-Forwarding

Istio routing rules are not applied to traffic sent over a Kubernetes port-forward connection.

Discussion on this: <https://discuss.istio.io/t/how-does-kubectl-port-forward-bypass-envoy-mtls-enforcement/731>

## Application Templates

The Network Observability control-plane includes an [istio-service](templates/istio-service/README.md) application template.  Applications registering with this template are installed as a Kubernetes deployment with a matching service and included in the Istio service mesh.  Applications registering as an istio-service might use the following example:

```yaml
template: istio-service
deployments:
  current:
    target: current
    clusters: 1
    values:
      name: app-v1
      versionIndependentName: dotnet-app
      version: "v1"
      image: ghcr.io/testuser/app-v1:main
      port: 5000
```

### Canary Deployments

The `istio-service` template also supports canary deployments which are enabled using the `canary: true` flag.  With this flag enabled, additional parameters are exposed to configure application versioning and traffic distribution.  The following is an example of an application registering with two versions, a current and a canary:

```yaml
template: istio-service
deployments:
  current:
    target: current
    clusters: 1
    values:
      name: app-v1
      versionIndependentName: dotnet-app
      version: "v1"
      image: ghcr.io/testuser/app-v1:main
      port: 5000
  canary:
    target: current
    clusters: 1
    values:
      canary: true
      name: app-v2
      versionIndependentName: dotnet-app
      version: "v2"
      weight: 10
      currentVersion: "v1"
      currentWeight: 90
      image: ghcr.io/testuser/app-v2:main
      port: 5000
```

In this example, the `current` deployment registers version 1 of the app and registers it in the service mesh with standard / default Istio routing rules.  The `canary` deployment registers version 2 of the app and enables the `canary: true` flag.  By enabling this flag, additional parameters are exposed to specify the desired traffic distribution between the apps.  In this example, 90% of the traffic is routed to version 1 and 10% is routed to version 2.

### Istio-Service Template Doc

More info on the istio-service application template can be found in the [template's doc](templates/istio-service/README.md).

## References

- Istio docs: <https://istio.io/latest/docs/>
- Istioctl docs: <https://istio.io/latest/docs/reference/commands/istioctl/>
- Istio Helm charts: <https://github.com/istio/istio/tree/master/manifests/charts>
- Base Helm chart: <https://github.com/istio/istio/tree/master/manifests/charts/base>
- Istiod Helm chart: <https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery>
- Istio Prometheus integration: <https://istio.io/latest/docs/ops/integrations/prometheus/>
- Istio Kiali integration: <https://istio.io/latest/docs/ops/integrations/kiali/>
- Istio metrics list: <https://istio.io/latest/docs/reference/config/metrics/>
- Istio Routing Not Applied to Ingress Gateway Requests: <https://istio.io/latest/docs/ops/common-problems/network-issues/#route-rules-have-no-effect-on-ingress-gateway-requests>
