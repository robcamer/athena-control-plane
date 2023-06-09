# Centralized Logging for the Network Observability Solution - Cloud Native

**Author:** Marshall Bentley
**Date:** 10/25/2022

## Overview

Centralized logging is an important component of any production-grade infrastructure, but it is especially critical in a containerized architecture. If you’re using Kubernetes to run your workloads, there’s no easy way to find the correct log “files” on one of the many worker nodes in your cluster. Kubernetes will reschedule your pods between different physical servers or cloud instances. Pod logs can be lost or, if a pod crashes, the logs may also get deleted from disk. Without a centralized logging solution, it is practically impossible to find a particular log file located somewhere on one of the hundreds or thousands of worker nodes. For this reason, any production-grade cluster should have its log collector agents configured on all nodes and use a centralized storage.

## Components

For centralized logging, the Network Observability control-plane uses [Fluentbit](https://docs.fluentbit.io/manual) for log aggregation, [Elasticsearch](https://www.elastic.co/guide/en/enterprise-search/current/index.html) for log persistence and querying and [Kibana](https://www.elastic.co/guide/en/kibana/current/index.html) for log search and visualization.  When used together, these tools are sometimes referred to as the EFK Stack.  Like our tools for monitoring, they are widely used, open source, are well documented and have wide community support and adoption.

Our Network Observability control-plane uses the following Helm charts:

- Fluentbit: <https://github.com/fluent/helm-charts/tree/main/charts/fluent-bit>
- Elasticsearch: <https://github.com/bitnami/charts/tree/main/bitnami/elasticsearch>
- Kibana: <https://github.com/bitnami/charts/tree/main/bitnami/kibana>

Fluentbit uses the ["es" output plugin](https://docs.fluentbit.io/manual/pipeline/outputs/elasticsearch) to publish logs to Elasticsearch.  It is noteworthy to mention, Elasticsearch does not permit dots "." in field names beyond a certain version.  Because of this it is required to configure the es plugin to replace dots with underscores using the following config:

```text
Replace_Dots On
```

Without this, Fluentbit errors like the following will be encountered:

```text
[engine] failed to flush chunk '1-1617054818.967282961.flb', retry in 9 seconds: task_id=0, input=tail.0 > output=es.0 (out_id=0)
```

## Control-Plane Integration

Monitoring and centralized logging services are added to the Network Observability control-plane as dial tone services.  They are registered as `ManifestDeployment` objects under `applications/coral-system/ManifestDeployments` with accompanying files under the `manifests` directory.  The following output shows the file structure using Elasticsearch as an example:

```text
applications/
└── coral-system
    └── ManifestDeployments
        ├── elasticsearch.yaml
manifests/elasticsearch/
├── kustomization.yaml
├── patches
│   └── prometheus-config.yaml
├── release.yaml
└── repository.yaml
```

Helm charts are customized using Coral patches.  More info on patches can be found here: <https://github.com/microsoft/coral/blob/main/docs/platform-patch-manifest.md>

## References

- Fluentbit Docs: <https://docs.fluentbit.io/manual>
- Elasticsearch Docs: <https://www.elastic.co/guide/en/enterprise-search/current/index.html>
- Kibana Docs: <https://www.elastic.co/guide/en/kibana/current/index.html>
