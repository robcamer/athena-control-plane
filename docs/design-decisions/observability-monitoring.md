# Observability and Monitoring for the Network Observability Solution - Cloud Native

**Author:** Marshall Bentley
**Date:** 10/25/2022

## Context and Scope

Centralized logging is an important component of any production-grade infrastructure, but it is especially critical in a containerized architecture. If you’re using Kubernetes to run your workloads, there’s no easy way to find the correct log “files” on one of the many worker nodes in your cluster. Kubernetes will reschedule your pods between different physical servers or cloud instances. Pod logs can be lost or, if a pod crashes, the logs may also get deleted from disk. Without a centralized logging solution, it is practically impossible to find a particular log file located somewhere on one of the hundreds or thousands of worker nodes. For this reason, any production-grade cluster should have its log collector agents configured on all nodes and use a centralized storage.

## Monitoring

This control-plane leverages Prometheus and Grafana to implement its monitoring solution.  Both tools are able to function in disconnected scenarios and do not rely on resources external to the Kubernetes cluster.  They are open source, have a wealth of documentation and examples and are widely used throughout the industry.  Prometheus is a Cloud Native Computing Foundation (CNCF) "graduated" project.

### Helm Charts

Our Network Observability control-plane uses the following Helm charts:

- Prometheus: <https://github.com/prometheus-community/helm-charts>
- Grafana: <https://github.com/grafana/helm-charts>

### Prometheus Annotations

The Network Observability control-plane uses Kubernetes `prometheus.io` annotations to configure Prometheus monitoring of applications and services.  When Prometheus sees pods with these annotations, it monitors them for metrics.  The control-plane's dial tone services are preconfigured with these.  Applications wishing to be monitored should also include them:

```text
prometheus.io/scrape: "true"
prometheus.io/port: "<your port>" e.g.: "9114"
prometheus.io/path: "<your metrics API>" e.g.: "/metrics"
```

Applications should be configured to publish metrics on the port and API specified in the annotations.  Many Helm charts include an option to expose / publish metrics.  Custom applications can use [Prometheus client libraries](https://prometheus.io/docs/instrumenting/clientlibs/) along with tools like [OpenTelemetry](https://opentelemetry.io/) to publish metrics.

### Grafana Dashboards

Grafana and its community publish [a library of open-source dashboards](https://grafana.com/grafana/dashboards/).  These dashboards can be included in the Helm installation either by embedding their source directly or by referencing them via id.  In both cases they are initialized and ready for use at startup.  The Network Observability solution makes use of several of these dashboards to monitor dial tone services such as the Istio service mesh, Elasticsearch and RabbitMQ.  An overview of the included dashboards follows:

#### Istio Dashboards

- [Mesh Dashboard](https://grafana.com/grafana/dashboards/7639): provides an overview of all services in the mesh.
- [Service Dashboard](https://grafana.com/grafana/dashboards/7636): provides a detailed breakdown of metrics for a service.
- [Workload Dashboard](https://grafana.com/grafana/dashboards/7630): provides a detailed breakdown of metrics for a workload.
- [Performance Dashboard](https://grafana.com/grafana/dashboards/11829): monitors the resource usage of the mesh.
- [Control Plane Dashboard](https://grafana.com/grafana/dashboards/7645): monitors the health and performance of the control plane.

#### Elasticsearch Dashboards

- [Elasticsearch](https://grafana.com/grafana/dashboards/6483): provides an overview of the Elasticsearch service.

#### RabbitMQ Dashboards

- [RabbitMQ Overview](https://grafana.com/grafana/dashboards/10991): provides an overview of the RabbitMQ service.

#### Additional Dashboards

Additional dashboards are included for Kubernetes, Network Observability, Application Observability, etc.

## References

- OpenTelemetry: <https://opentelemetry.io/docs/concepts/what-is-opentelemetry/>
- Prometheus Client Libraries: <https://prometheus.io/docs/instrumenting/clientlibs/>
- Grafana Dashboard Library: <https://grafana.com/grafana/dashboards/>
