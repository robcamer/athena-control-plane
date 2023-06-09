#!/usr/bin/env bash

set -euo pipefail

if [[ "$DEPLOY_INFRA" != "true" ]]; then
    echo "Infrastructure deployment not required, skipping..."
    exit 0
fi

readonly state_file=infrastructure/state

if [[ -f $state_file ]]; then
    state_rg=$(awk '/RESOURCE_GROUP_NAME/  { print $2 }' $state_file)
    state_kv=$(awk '/KEYVAULT_NAME/  { print $2 }' $state_file)
    state_staccnt=$(awk '/STORAGE_ACCOUNT_NAME/  { print $2 }' $state_file)
    state_acr=$(awk '/ACR_NAME/  { print $2 }' $state_file)
    state_aks=$(awk '/AKS_NAME/  { print $2 }' $state_file)
fi

random_seed=$(head -c 5 <(fold -w 20 <(tr -dc 'a-z0-9' </dev/urandom)))

readonly random_seed
readonly workload=${WORKLOAD_NAME:-"ntwkobsv"}
readonly region=${REGION:-"eastus"}
readonly env=${DEPLOY_ENV:-"dev"}
readonly resource_group_name=${RESOURCE_GROUP_NAME:-${state_rg:-"rg-${workload}-${env}-${random_seed}"}}
readonly staccnt_name=${STORAGE_ACCOUNT:-${state_staccnt:-"st${workload}${env}${random_seed}"}}
readonly akv_name=${AKV_NAME:-${state_kv:-"kv-${workload}-${env}-${random_seed}"}}
readonly acr_name=${ACR_NAME:-${state_acr:-"cr${workload}${env}${random_seed}"}}
readonly aks_name=${AKS_NAME:-${state_aks:-"aks-${workload}-${env}-${random_seed}"}}
readonly vm_size=${VM_SIZE:-"standard_e2ds_v5"}

function commit() {
    if [ -n "$(git status clusters infrastructure templates/istio-service/deploy --porcelain)" ]; then
        echo "Commiting State update..."
        git pull
        git add clusters infrastructure/state templates/istio-service/deploy
        [[ $source_control = "--github" ]] && commit_msg="[no ci] Updated cluster yaml and infrastructure state $SHA" || commit_msg="[ci skip] Updated cluster yaml and infrastructure state"
        [ -n "$(git diff-index --cached HEAD)" ] && git commit -m "$commit_msg"
        git push origin
    fi
}

trap commit EXIT

function pushToState() {
    local -r name=$1
    local -r value=$2

    if [[ ! -f $state_file ]]; then
        echo "${name}: ${value}" >>$state_file
    else
        if grep -qF "${name}" $state_file; then
            sed -i "s/${name}.*/${name}: ${value}/" $state_file
        else
            echo "${name}: ${value}" >>$state_file
        fi
    fi
}

if [[ -z ${1:-} ]]; then
    echo "Error: No source control parameter passed!"
    echo "Expected either --github or --gitlab"
    exit 1
else
    source_control=$1
fi

###### Resource Group ######
if az group list --output tsv | grep "$resource_group_name" -q; then
    echo "Azure Resource Group: $resource_group_name already exists! Skipping creation!"

    pushToState RESOURCE_GROUP_NAME "$resource_group_name"
else
    echo "Create Azure Resource Group...$resource_group_name."
    az group create \
        --name "$resource_group_name" \
        --location "$region"

    pushToState RESOURCE_GROUP_NAME "$resource_group_name"
fi
##############################

####### Key Vault #######
if az keyvault list --resource-group "$resource_group_name" --output tsv | grep "$akv_name" -q; then
    echo "Azure Keyvault: $akv_name already exists! Skipping creation!"

    pushToState KEYVAULT_NAME "$akv_name"
else
    echo "Create Azure Keyvault...$akv_name"
    az keyvault create \
        --name "$akv_name" \
        --resource-group "$resource_group_name" \
        --location "$region"

    pushToState KEYVAULT_NAME "$akv_name"
fi
##############################

##### CONTAINER REGISTRY #####
if az acr list --resource-group "$resource_group_name" --output tsv | grep "$acr_name" -q; then
    echo "Azure Container Registry: $acr_name already exists! Skipping creation!"

    pushToState ACR_NAME "$acr_name"
else
    echo "Create Azure Container Registry...$acr_name"
    az acr create \
        --resource-group "$resource_group_name" \
        --name "$acr_name" \
        --sku Basic \
        --admin-enabled

    pushToState ACR_NAME "$acr_name"
fi
##############################

###### STORAGE ACCOUNT ######
if az storage account list --resource-group "$resource_group_name" --output tsv | grep "$staccnt_name" -q; then
    echo "Storage Account: $staccnt_name already exists! Skipping creation!"

    pushToState STORAGE_ACCOUNT_NAME "$staccnt_name"
else
    echo "Create Storage Account...$staccnt_name"
    az storage account create \
        --name "$staccnt_name" \
        --resource-group "$resource_group_name" \
        --location "$region" \
        --sku Standard_LRS \
        --kind StorageV2

    pushToState STORAGE_ACCOUNT_NAME "$staccnt_name"

    account_key=$(az storage account keys list -g "$resource_group_name" -n "$staccnt_name" --query [0].value | tr -d \")

    az storage share create \
        --account-name "$staccnt_name" \
        --account-key "$account_key" \
        --name netobs
fi

sed -i "s/resourceGroup.*/resourceGroup: ${resource_group_name}/" templates/istio-service/deploy/azurefile-csi-pv.yaml
sed -i "s/storageAccount.*/storageAccount: ${staccnt_name}/" templates/istio-service/deploy/azurefile-csi-pv.yaml
sed -i "s/shareName.*/shareName: netobs/" templates/istio-service/deploy/azurefile-csi-pv.yaml
##############################

############ AKS ############
if az aks list --resource-group "$resource_group_name" --output tsv | grep "$aks_name" -q; then
    echo "Azure Kubernetes Service: $aks_name already exists! Skipping creation!"

    pushToState AKS_NAME "$aks_name"
else
    echo "Create Azure Kubernetes Service...$aks_name"
    az aks create \
        --resource-group "$resource_group_name" \
        --name "$aks_name" \
        --max-count 10 \
        --min-count 5 \
        --node-count 8 \
        --enable-cluster-autoscaler \
        --node-vm-size "$vm_size" \
        --auto-upgrade-channel stable \
        --enable-managed-identity \
        --no-ssh-key \
        --network-plugin azure \
        --attach-acr "$acr_name"

    cat <<EOF >clusters/"$env".yaml
kind: Cluster
metadata:
  name: $env
  labels:
    cloud: $AZURE_CLOUD
    region: $region
    aksClusterName: $aks_name
    aksClusterResourceGroup: $resource_group_name
spec:
  environments:
    - $env
EOF

    pushToState AKS_NAME "$aks_name"

fi
##############################
