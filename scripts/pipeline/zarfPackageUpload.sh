#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used for creating and uploading Zarf packages/scripts to an Azure Storage Account
# * Environment Variables
#   * Name: CONTAINER_REGISTRY_URL
#   * Value: Container registry URL eg. <acrname>.azurecr.us
#   * Name: CONTAINER_REGISTRY_ACCESS_TOKEN
#   * Value: Container registry Access Token (Local only)
#   * Name: CONTAINER_REGISTRY_USER
#   * Value: Container registry username eg. <acrname>
#   * Name: RESOURCE_GROUP_NAME
#   * Value: Azure Storage Account Resource Group
#   * Name: STORAGE_ACCOUNT
#   * Value: Azure Storage Account Name in the Resouce Group above
#   * Name: GITOPS_REPO
#   * Value: GitOps repo initialized with this Control Plane
#   * Name: GITHUB_USER
#   * Value: GitHub user with access to the GitOps repo
#   * Name: GITHUB_TOKEN
#   * Value: GitHub user PAT with access to the GitOps repo
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

if [[ -z "${GITHUB_SHA:-}" && -z "${GITLAB_TOKEN:-}" ]]; then readonly pipeline=false; else readonly pipeline=true; fi
if [[ -z "${GITHUB_SHA:-}" ]]; then readonly github=false; else readonly github=true; fi
if [[ -z "${GITLAB_TOKEN:-}" ]]; then readonly gitlab=false; else readonly gitlab=true; fi

[[ $pipeline = "true" ]] && readonly state_file=controlplane/infrastructure/state || state_file=infrastructure/state

if [[ -f $state_file ]]; then
    state_rg=$(awk '/RESOURCE_GROUP_NAME/  { print $2 }' $state_file)
    state_staccnt=$(awk '/STORAGE_ACCOUNT_NAME/  { print $2 }' $state_file)
    state_acr=$(awk '/ACR_NAME/  { print $2 }' $state_file)
    state_akv=$(awk '/KEYVAULT_NAME/  { print $2 }' $state_file)
fi

readonly resource_group_name=${RESOURCE_GROUP_NAME:-$state_rg}
readonly staccnt_name=${STORAGE_ACCOUNT:-$state_staccnt}
readonly acr_name=${ACR_NAME:-$state_acr}
readonly akv_name=${AKV_NAME:-$state_akv}
declare  storage_container_name="zarf-container-local"

init() {
    if [[ "$pipeline" = false ]]; then
        # Local execution - $HOME/.env required
        if [ -f ~/.env ]; then
            set -o allexport
            # shellcheck source=/dev/null
            source ~/.env set
            set +o allexport
        fi
    else
        # Pipeline execution
        repo=$(sed "s/\//\-/g" <<<"${GITHUB_REPOSITORY:-}")
        [[ "$github" = true ]] && storage_container_name="zarf-$repo-$GITHUB_RUN_NUMBER"
        [[ "$gitlab" = true ]] && storage_container_name="zarf-$CI_PROJECT_NAME-$CI_JOB_ID"
        echo "Pipeline storage container: $storage_container_name"

        # Reanining operations are in the Control Plane repo (cloned to controlplane folder via the pipeline)
        cd controlplane

        echo "ls zarf"
        ls zarf
    fi
    readonly run_zarf=${RUN_ZARF:-false}
}

zarf_package_upload() {
    # Creates an individual Zarf package and uploads it to the Storage Account
    local folder=$1
    rm -f "$folder"/*tar.zst
    zarf package create "$folder" -o "$folder" --confirm
    package=$(ls "$folder"/*tar.zst*)
    az storage blob upload -f "$package" -c "$storage_container_name" --overwrite true
}

create_script="\n# Package creation"

create_upload_zarf_packages() {
    # Package zarf.yamls and upload to storage container
    for folder in ./zarf/*; do
        if [ -f "$folder/zarf.yaml" ]; then
            if [[ "$run_zarf" = true ]]; then
                # package and upload
                zarf_package_upload "$folder"
            elif [[ $(find "$folder" -type f -name "*.tar.zst" | wc -l) -eq 0 ]]; then 
                # create dummy file for scripts if none exists
                package_name=$(yq '.metadata.name' "$folder/zarf.yaml")
                echo "# Fake zarf package" >"$folder/zarf-package-$package_name-amd64.tar.zst"
            fi
            create_script="${create_script}\nzarf package create $folder -o $folder --confirm --no-progress"
        fi
    done
}

generate_scripts() {
    # Generate helper scripts for deployment
    local create="./zarf/create.sh"
    local deploy="./zarf/deploy.sh"
    local local="./zarf/local.sh"
    local upload="./zarf/upload.sh"
    local bash="#!/bin/bash"

    rm -f $create $deploy $upload
    write_file $create $bash new
    write_file $deploy $bash new
    write_file $upload $bash new

    # create file
    write_file $create "\n# Docker login"
    write_file $create "accessToken=\$(az acr login --name $acr_name --expose-token --output tsv --query accessToken --only-show-errors)"
    write_file $create "echo \$accessToken | docker login $acr_name$(get_acr_domain) -u 00000000-0000-0000-0000-000000000000 --password-stdin"
    write_file $create "$(echo -e "${create_script}")"

    # deploy file
    write_file $deploy "\n# Add RKE local path storage class"
    write_file $deploy "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml"  
    write_file $deploy "kubectl annotate --overwrite storageclass local-path storageclass.kubernetes.io/is-default-class=true"  

    write_file $deploy "\n# Zarf init cluster"
    write_file $deploy "zarf init --confirm --no-progress"  

    write_file $deploy "\n# Sealed Secret decryption secret"
    write_file $deploy "kubectl create namespace infrastructure"
    write_file $deploy "kubectl label --overwrite namespace infrastructure istio-injection=enabled"
    write_file $deploy "az keyvault secret show --name sealed-secrets-key --vault-name $akv_name --query 'value' -o tsv | base64 --decode | kubectl apply -f -"
    write_file $deploy "\n# Grafana SQL Datasource config map (Sealed Secrets cannot encrypt configmaps)"
    write_file $deploy "sql_password=\$(az keyvault secret show --name azure-sql-edge-password --vault-name $akv_name --query 'value' -o tsv | base64 --decode)"
    write_file $deploy "cat zarf/azure-sql-edge/datasource.yaml | sed \"s/<edge-sql-password>/\$sql_password/g\" | kubectl apply -f -"
    
    write_file $deploy "\n# Note: Deployment order is critical for the first few packages"
    write_file $deploy "\n# Package download"
    write_file $deploy "# az storage blob download-batch -d . \\
#   --pattern '*.zst' \\
#   --source $storage_container_name \\
#   --account-name '<storage-account-name>' \\
#   --account-key '<storage-account-key>' \\
#   --dryrun"
    write_file $deploy "\n# Package deploy (downloaded)"

    # upload file
    write_file $upload "\n# Package upload"

    # prioritize Zarf deployment order
    mapfile -t zarf_all < <(find zarf -type f -name "*.tar.zst" -exec dirname "{}" \; | sort)
    declare -A zarf_priority_map
    counter=200
    for zarf_folder in "${zarf_all[@]}"; do
        priority=$counter
        if [[ -f "$zarf_folder/priority.yaml" ]]; then priority=$((100 + $(cat "$zarf_folder/priority.yaml"))); else ((counter=counter+1)); fi
        zarf_priority_map["$priority"]=$zarf_folder
    done
    
    echo "# Prioritized deployments"
    KEYS=$(echo ${!zarf_priority_map[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
    for KEY in $KEYS; do
        zarf_folder=${zarf_priority_map[$KEY]}
        echo "KEY=[$KEY] VAL=[$zarf_folder]"
        if [[ $KEY -eq 200 ]]; then
            write_file $deploy "# No priority"
            write_file $local "# No priority"
        fi
        zarf_file=$(find "$zarf_folder" -type f -name "*.tar.zst")
        write_file $deploy "# zarf package deploy $(basename "$zarf_file") --no-progress --confirm"
        write_file $local "zarf package deploy $zarf_file --no-progress --confirm"
    done

    # generate upload
    find zarf -type f -name "*.tar.zst" | sort | while read -r item; do
        write_file $upload "az storage blob upload -f $item -c ${storage_container_name} --overwrite true &"
    done
    write_file $upload "wait"
    write_file $deploy "\n# Package deploy (local)"
    write_file $deploy "$(cat $local)" && rm -f $local

    # zip of manifests
    folder="zarf-mainfests.tar.gz"
    if [[ -d controlplane ]]; then
        tar --exclude='*.zst' -zcf $folder controlplane/zarf
    else
        tar --exclude='*.zst' -zcf $folder zarf
    fi

    # upload scripts and assets
    if [[ "$run_zarf" = true ]]; then
        az storage blob upload -f $create -c "$storage_container_name" --overwrite true
        az storage blob upload -f $deploy -c "$storage_container_name" --overwrite true
        az storage blob upload -f $upload -c "$storage_container_name" --overwrite true
        az storage blob upload -f $folder -c "$storage_container_name" --overwrite true
    fi

    # log output
    packages=$(find zarf -type f -name "*.tar.zst" | awk -F"/" '{print $NF}' | sort)
    [[ -n "$packages" ]] && echo -e "\n# Packages Created\n$packages"
    echo -e "$(cat $deploy)"

    rm -rf zarf/gitops-* zarf-mainfests.tar.gz
    if [[ -d zarf ]]; then chmod +x ./zarf/*; fi
    if [[ -d controlplane ]]; then chmod +x ./controlplane/zarf/*; fi

    echo "Zarf processing completed"
    # find zarf -type f -name "*.tar.zst" -exec rm {} \;
}

write_file() {
    local file=$1
    local content=$2
    local new=${3:-""}
    if [[ -n $new ]]; then echo -e "$content" >"$file"; else echo -e "$content" >>"$file"; fi
}

init
if [[ "$run_zarf" = true ]]; then 
    login_container_registry "$acr_name"
    set_storage_account_connection_string "$resource_group_name" "$staccnt_name"    
    create_blob_container "$storage_container_name"
fi
create_upload_zarf_packages
generate_scripts
