# Service Specific Dashboard Configuration for Grafana

**Author:** Swetha Anand
**Date:** 1/6/2023

## Overview

The Platform Team might be contacted by the Service/App Team to get the network-observability dashboard configured for them in the control-plane.

The control plane seed avoids including application service specific configuration, however, once an instance of the control plane is created, it is expected that there will be application service specific configuration that will need to be applied to the control plane instance. For example, only infrastructure focused Grafana dashboards are included by default.

Application services will often require additional configuration applied to the control plane instance. For example, this could be environment variables that injected into the running container or additional application specific Grafana dashboards.

## Changes needed to configure the network-observability dashboard

Once platform team receives the json from app team the platform team will need to add that json to the instance of control plane at manifest/grafana/patches/dashboard-config.yaml as below. For example:

```bash
network-observability:
    json: |
        {"annotations": ## json from service team#
    datasource: mssql
```

Once the json is configured, the configuration required for mssql datasource can be done under instance of control plane at manifest/grafana/patches/datasource-config.yaml. For example:

```bash
    # Configuration needed for network-observability dashboard ##
    - name: mssql
      type: mssql
      url: azure-sql-edge-service.infrastructure.svc.cluster.local:1433
      database: #databasename#
      user: sa
      secureJsonData:
        password: #Update the password#
      isDefault: true
```
