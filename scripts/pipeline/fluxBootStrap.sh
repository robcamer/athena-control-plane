#!/bin/bash

set -eo pipefail

########
# Description:
# * Script used to bootstrap flux onto cluster
########

if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi
echo "Flux bootstrap.sh"

for cluster in clusters/*.yaml; do
    echo "cluster: $cluster"
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")
    cluster_info=$(yq '.metadata.name' "$cluster")
    echo "cluster_info: $cluster_info"

    # Get cluster's k8s credentials
    az aks get-credentials \
        --resource-group "$cluster_rg" \
        --name "$cluster_name" \
        --overwrite-existing

    if [[ -z ${1:-} ]]; then
        echo "Error: No source control parameter passed!"
        echo "Expected either --github or --gitlab"
        exit 1
    else
        source_control=$1
    fi

    echo "Flux bootstrap with AKS"
    flux_installed=$(kubectl get svc -n flux-system --ignore-not-found=true | wc -l)
    if [[ "$flux_installed" -eq "0" ]]; then
        echo "Installing Flux..."
        if [[ $source_control = "--github" ]]; then
            flux bootstrap github --owner="$GITOPS_REPO_OWNER" \
                --repository="$GITOPS_REPO" \
                --branch=main \
                --path="clusters/$cluster_info" \
                --personal \
                --network-policy=false \
                --timeout 10m0s
        elif [[ $source_control = "--gitlab" ]]; then
            export GITLAB_TOKEN="$ACCESS_TOKEN" # Need an explicit export for gitlab to pick up
            flux bootstrap gitlab --hostname="$GITLAB_HOST" \
                --token-auth \
                --owner="$GITOPS_REPO_OWNER" \
                --repository="$GITOPS_REPO" \
                --branch=main \
                --namespace=flux-system \
                --path="clusters/$cluster_info" \
                --timeout 10m0s
        fi
    else
        echo "Number of Flux services found:"
        echo $((flux_installed - 1))

        flux reconcile kustomization flux-system &
    fi
done
