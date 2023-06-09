# Istio Sample 

This deployment is only included to demonstrate the service mesh functionality and is not part of the solution. The hello world example is used from the main [Istio repo](https://github.com/istio/istio) and modified for a non-gateway implementation as this is outside the sample scope for disconnected scenarios.

## Pre-requisites

- Both Istio base and Istiod deployments have to be deployed to the cluster
- The namespace in which this hello world package deploys into must have the required istio label (currently infrastructure)

## Running the sample

Once the package is created and deployed, the Service will refer to both deployments, V1 and V2. The Virtual Service however routes traffic to various deployment versions as declared in its yaml. Adjust the weights to test various scenarios. The current disposition is to send all traffic to the V2 deployment.

```bash
# virtual-service.yaml
# ...
    - destination:
        host: helloworld
        subset: "v1"
        port:
          number: 5000
      weight: 0
    - destination:
        host: helloworld
        subset: "v2"
        port:
          number: 5000
      weight: 100
```

The Ubuntu pod is included for testing from within the cluster with the `curl` command.

Firstly, terminal into the Ubuntu pod. Since this is a base OS, we need to install curl.

```bash
# terminal into ubuntu pod from infrastructure namespace
kubectl exec -it ubuntu -- /bin/bash

# Install curl on Ubuntu
apt-get update
apt-get upgrade
apt-get install -y --no-install-recommends curl
```

Next we can test the http request to the helloworld service.

```bash
# curl response for 100% V2
while true; do curl helloworld:5000/hello; sleep 1; done

Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
```

We can delete the virtual serivce resource directly from the cluster using `kubectl delete -f virtual-service.yaml` and then modify the weights, then redeploy using `kubectl apply -f virtual-service.yaml`. Using a 50/50 split we can achieve a new curl response as follows.

```bash
# curl response for a 50/50 weighted split
while true; do curl helloworld:5000/hello; sleep 1; done

Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v1, instance: helloworld-v1-77489ccb5f-xggxj
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v2, instance: helloworld-v2-7bd9f44595-xgc8h
Hello version: v1, instance: helloworld-v1-77489ccb5f-xggxj
```

## Conclusion

The istio service mesh allows dynamic load balancing on the service level and handles traffic via its virtual service weighting. The current application solution leverages this for inter cluster traffic. This sample is used to illustrate routing with a simple example which can be followed for your own service oriented architecture needs.

## References

- <https://istio.io/latest/docs/setup/install/helm/>
- <https://github.com/istio/istio>