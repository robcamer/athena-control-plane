# RKE2 Kubernetes distribution with Zarf

**Author:** Dave Seepersad
**Date:** 03/20/2023

## Overview

[Zarf](https://zarf.dev/) is a tool for deploying to disconnected Kubernetes clusters by packaging the yaml and image assets into a single portable file to be installed on a Zarf initialized cluster.

In this article we document the process of deploying the network-observability-control-plane to RKE2 Cluster with Zarf.

## Pre-requisites

### RKE 2

Create the RKE instance by following the [cluster.md](cluster.md) document.

### Zarf

Install the Zarf CLI and download the zarf init package locally. Find the latest version in the [Zarf GitHub](https://github.com/defenseunicorns/zarf/releases) release page.

```bash
zarf_version=v0.24.2

# Install Zarf
curl -sL "https://github.com/defenseunicorns/zarf/releases/download/${zarf_version}/zarf_${zarf_version}_Linux_amd64" -o /usr/local/bin/zarf
chmod +x /usr/local/bin/zarf

# Retrieve init package (or may have an error that it is not available)
wget https://github.com/defenseunicorns/zarf/releases/download/${zarf_version}/zarf-init-amd64-${zarf_version}.tar.zst
chmod +x zarf-init-amd64-${zarf_version}.tar.zst
mkdir -p $HOME/.zarf-cache
mv zarf-init-amd64-${zarf_version}.tar.zst $HOME/.zarf-cache
```

### Storage

AKS deployments focus on Azure File backed Storage Classes. In this example however, we will use the Local-Path storage class to illustrate disconnected portability. These will be leveraged for both dial tone and application deployments.

Network Observability Apps such as pcap ingestor/processor, event processor, netstats generator uses will use dedicated PV & PVC. These can reference the same file path on the RKE host machine. Files are copied to this storage via `kubectl cp` from your local device to the relevant pod (detailed below).

## Deployment

### Steps

Before getting started, please complete [network observability control plane guide](../../README.md) in the main repo. The Zarf deployment of apps can only be facilitated by first registering the apps with the Control Plane and leveraging the GitOps rendered yaml for these apps. Once the Zarf yamls are created, the pipeline and AKS instances are no longer necessary as the packages can be created locally and deployed.

>**Note** The pipeline does not create the RKE 2 instance nor does it deploy the Zarf packages to one. The zarf yamls are a created/saved in the control plane and the pipeline can additionally create and place the actual packages with images in a Storage Account Container awaiting transfer and deployment.

In the pipeline deployment, the packages are created and then need to be downloaded from the container before they can be deployed. To zarf package create and upload from the pipeline:

- In GitHub pipeline's you can select the `Select to run Zarf package and upload` run workflow checkbox or commit with `RUN_ZARF` as part of the message.
- In GitLab you have to set the `RUN_ZARF: 'false'` variable in the pipeline `.gitlab-ci.yml` file to true.

These instructions will focus on the local deployment.

  1. Download the latest Control Plane code once the standard GitOps deployment with dial tone services and applications are successful with `git pull`.
  2. Review the pipeline generated assets which are saved to the `/zarf` folder.
     - application folders are present with zarf.yaml files
     - automation scripts are present (run from the root folder)
       - create.sh - Registry login and zarf creation
       - deploy.sh - Deploy dependencies, download from container and prioritized package deploy commands
       - upload.sh - Upload local packages to storage container
  3. Run the create.sh script which will create all packages locally. The first time you run this it will take a long time as it has to retrieve all images in a serial execution chain. Subsequent runs utilize the cached images in the `~/.zarf-cache` folder.
  4. Retrieve the RKE 2 kubeconfig. If using the RancherFederal terraform deployment this is saved in the RKE resource Group's Key Vault, otherwise refer to your own RKE install docs. Merge this kubeconfig into your own locally and set to the current context before performing the deployment steps.

You can add this function to your `~/.bashrc` file and call it with `mergeKubeconfig <path to file with rke kubeconfig>` or follow the [steps manually](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/).

```bash
# optional helper, add to ~/.bashrc
function mergeKubeconfig() {
    local newConfig=$1
    if [[ -n $newConfig ]]; then
        cp ~/.kube/config ~/.kube/config.bak
        KUBECONFIG=~/.kube/config:$newConfig kubectl config view --flatten > /tmp/config 
        mv /tmp/config ~/.kube/config
        chmod go-r ~/.kube/config
        
        echo "Success: config merged"
    else
        echo "Error: No config supplied"
    fi
}

# restart your terminal

# now you can run this with your RKE kubeconfig file, e.g.
$ mergeKubeconfig /home/user/rke-kubeconfig.yaml
Success: config merged

# set context, e.g. default is the name of my RKE config
$ kubectl config use-context default 
Switched to context "default".
```

  5. Run the deploy.sh script. You can also run individual commands, the order is important.
     - This will take a few hours, especially if the RKE cluster is remote, adding upload time.
     - The `Zarf init` command itself can take more than half an hour with the injector describe displaying a message "waiting for node preemption condition". Hopefully this can be improved in future releases. Note the `kubectl label nodes <your node name> nodePool=cluster` command may help.
     - This will take a long time (all images are included with each package).
     - If working with downloaded packages then uncomment/comment the relevant sections.
     - Prioritization of the package order is accomplished by a `priority.yaml` file in each folder. The lower the number, the higher the priority.
     - Folders with no priority show in alphabetical order after the prioritized deployments.
     - Caution, if two folders have the same priority file number, then only one will appear in the deployment script.
  6. Upload the zip and event files to the cluster. This example transfers both files from the user's root folder `~/`.
   
```bash
kubectl cp <path-to-zip> <pcap-ingestor-namespace>/<ingestor-pod-name>:/var/data/validation/
kubectl cp <path-to-event> <event-processor-namespace>/<event-pod-name>:/var/data/metadata/

# e.g.
kubectl cp ~/airtunes.zip ghdev-zarf-pcap-ingestor/zarf-pcap-ingestor-v1-deployment-794bcbc769-b4g75:/var/data/validation/

kubectl cp ~/eventdata.json ghdev-zarf-event-processor/zarf-event-processor-v1-deployment-6cf9fc4674-hfp95:/var/data/metadata/
```

  6. Port forward to the Grafana pod to view the Network Observability dashboard.

```bash
kubectl port-forward <grafana-pod-name> 3000:3000

# e.g.
kubectl port-forward kube-prometheus-stack-grafana-d646fd9c4-xpk8q 3000:3000
```

## Scripts Involved

There are several Zarf script files located in this project `scripts/pipeline/zarf*.sh` and complete local or pipeline functionality.

 - zarfGetApps.sh 
   - Pipeline script for getting app yamls from GitOps repo. 
   - Can be run locally by cloning the GitOps repo to a `gitops` folder into this project.
   - Flattens the GitOps structure into a folder while preserving the workspace and cluster information to support multiple targets.
 - zarfGetChartImages.sh 
   - Local script for retrieving the latest Helm version and chart images for dial tone services.
   - This generates a `chart.txt` file in the zarf folder for easy reference when updating dial tone manifests.
 - zarfPackageUpload.sh
   - Local script for generating Zarf create, upload and deploy scripts.
   - Pipeline script for generating scripts plus creating and saving packages to a storage account container.

## Updating dial tone Zarf Helm packages

To update the dial tone helm charts the chart version and included images versions have to be retrieved. The `scripts/pipeline/zarfGetChartImages.sh` script does this for the releases used in this project. This generates a file in the `/zarf/` folder that lists the required information. Transfer this information to the `zarf.yaml` file to be updated.

Note there are some images not included as image tags in a helm release, they could be referenced in a script for example. The script cannot identify these images. The deployment will fail if not included, however the failed pod's describe output will specify which image is required and this can then be added to the `zarf.yaml` images list.

## Istio and Canary deployments

There is a /zarf/istio-sample deployment included to illustrate the service mesh routing of network traffic within the Zarf cluster using a virtual service. This folder has an included [readme.md](../../zarf/istio-sample/README.md) file that describes the deployment and testing strategy. It is not part of the Network Observability solution and therefore is self contained.

This was included since the solution focuses on storage access for operation and not service to service  weighted versions via network load balancing.

## Troubleshooting

The Zarf packages take some time to create and deploy, therefore debugging takes some time. Thankfully Zarf caches images locally in the ~/.zarf-cache folder and does not have to download it each time the package is created.

Packages themselves are composed of components that are deployed in order of placement in the `zarf.yaml` file. The Sealed secrets are deployed in its own component to ensure it is available to the subsequent resource (e.g. for RabbitMQ and SQL).

- Sometimes when a resource already exists which Zarf is trying to deploy, it may fail.
- If a chart has a dependency such as a CRD or StorageClass that is not previously installed, it will fail.
- If there is a health check and it fails, the deployment will fail
- The #zarf and #zarf-dev [Kubernetes Slack](https://kubernetes.slack.com/) channels have a lot of information and support users

## Limitations

The load balancing was not tested as a completely remote scenario was the configuration tested. Additionally the Istio Gateway chart does not deploy properly since it has an `auto` image which is a Kubernetes construct and not an actual image, causing Zarf to fail.

Grafana dashboards that are too big do not deploy properly. These dashboards were converted to base64 encode versions and worked as expected.

## References

- Local Path Provisioner: <https://github.com/rancher/local-path-provisioner>
- Zarf examples: <https://github.com/defenseunicorns/zarf/tree/main/examples>
- RKE2: <https://docs.rke2.io/>