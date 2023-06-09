#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used to deploy encryption keys
# * Reads in the SOPS private key from the key vault
# * For each cluster, creates the sops-age secret in the key vault
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

if [[ ! -d clusters ]] || [[ -z "$(ls -A clusters/*.yaml)" ]]; then exit 0; fi

# Get SOPS key
sops_private_key=$(get_akv_secret "$SOPS_PRIVATE_KEY_SECRET_NAME")
if [[ -z "$sops_private_key" ]]; then
    echo "SOPS private key does not exist in AKV, stopping..."
    exit
fi

for cluster in clusters/*.yaml; do
    cluster_name=$(yq '.metadata.labels.aksClusterName' "$cluster")
    cluster_rg=$(yq '.metadata.labels.aksClusterResourceGroup' "$cluster")

    # Get cluster's k8s credentials
    az aks get-credentials \
        --resource-group "$cluster_rg" \
        --name "$cluster_name" \
        --overwrite-existing

    sops_key_exists=$(kubectl get secret --namespace flux-system sops-age --output name --ignore-not-found=true | wc -l)
    if [[ "$sops_key_exists" -gt "0" ]]; then
        echo "SOPS key secret already exists on cluster ${cluster_name}, skipping secret deployment..."
        continue
    fi

    kubectl delete secret --namespace flux-system --ignore-not-found=true sops-age

    echo "get flux namespace"
    get_flux_namespace=$(kubectl get namespace flux-system --output name --ignore-not-found=true | wc -l)
    if [[ "$get_flux_namespace" -eq "0" ]]; then
        echo "flux-system namespace not found, creating flux-system namespace..."
        kubectl create namespace flux-system
    fi

    echo "$sops_private_key" |
        kubectl create secret generic sops-age \
            --namespace=flux-system \
            --from-file=age.agekey=/dev/stdin
done
