#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used for creating new files related to FLUX component
########

cd gitops
echo "createFluxGotk.sh"

for cluster in clusters/*/; do
    echo "cluster: $cluster"

    mkdir -p "$cluster"/flux-system
    if [[ -f $cluster/flux-system/gotk-components.yaml ]] || [[ -f $cluster/flux-system/gotk-sync.yaml ]] || [[ -f $cluster/flux-system/kustomization.yaml ]]; then exit 0; fi
    echo "flux kustomization files not found, creating..."
    touch "$cluster"/flux-system/gotk-components.yaml
    touch "$cluster"/flux-system/gotk-sync.yaml
    touch "$cluster"/flux-system/kustomization.yaml
done
