#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used for storing common functions
########

generate_password(){
    # Generate a random password, length optional
    [[ "$#" -ne 1 ]] && length=17 || length="$1"

    cut_length=$((length - 2)) # removes trailing ==
    echo "$(openssl rand -base64 "$length" | cut -c 1-$cut_length | sed 's/\//0/g' | sed 's/-/0/g')!="
}

base64_encode_one_line() {
    # Base64 encodes value in one string
    # Decode with 'echo "$encoded" | base64 --decode > decoded.txt' to preserve line breaks
    if [[ "$#" -ne 1 ]] || [[ -z "$1" ]]; then
        echo "Input must be in the format base64_encode_one_line <value to encode>"
        exit 1
    fi

    # Check which version of base64 is installed and set the option accordingly
    check=$(echo -n "$1" | base64 -w 0 2>&1)

    if [[ $check == *"invalid"* ]]; then 
        echo -n "$1" | base64 -b 0
    else
        echo "$check"
    fi
}

get_akv_secret() {
    # Gets an Azure Key Vault Secret
    if [[ "$#" -ne 1 ]] || [[ -z "$1" ]]; then
        echo "Input must be in the format get_akv_secret <AKV secret name>"
        exit 1
    fi

    az keyvault secret show --name "$1" --vault-name "$KEYVAULT_NAME" --query 'value' -o tsv
}

set_akv_secret() {
    # Gets an Azure Key Vault Secret
    if [[ "$#" -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Input must be in the format set_akv_secret <name> <value>"
        exit 1
    fi

    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$1" --value "$2" > /dev/null 2>&1
}

set_akv_file() {
    # Gets an Azure Key Vault Secret
    if [[ "$#" -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Input must be in the format set_akv_secret <name> <file>"
        exit 1
    fi

    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$1" --file "$2" > /dev/null 2>&1
}

does_akv_secret_exist() {
    # Checks if an Azure Key Vault Secret exists
    if [[ "$#" -ne 1 ]] || [[ -z "$1" ]]; then
        echo "Input must be in the format does_akv_secret_exist <AKV secret name>"
        exit 1
    fi

    az keyvault secret list --vault-name "$KEYVAULT_NAME" --query "contains([].name, '$1')"
}

set_storage_account_connection_string() {
    # Sets the Storage Account connection string for the Azure SP to use
    if [[ "$#" -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Input must be in the format set_storage_account_connection_string <resource_group_name> <staccnt_name>"
        exit 1
    fi
    AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string -g "$1" -n "$2" -o tsv)
    export AZURE_STORAGE_CONNECTION_STRING
}

create_blob_container() {
    # Creates a storage account container using the current connection string
    if [[ "$#" -ne 1 ]] || [[ -z "$1" ]]; then
        echo "Input must be in the format create_blob_container <storage_container_name>"
        exit 1
    fi

    az storage container create -n "$1"
}

get_acr_domain() {
    # Get the domain for the ACR based on the current Azure cloud

    AZURE_CLOUD=$(az cloud show --query name -o tsv)
    [[ "$AZURE_CLOUD" == "AzureUSGovernment" ]] && domain=".azurecr.us" || domain=".azurecr.io"

    echo "$domain"
}

get_akv_domain() {
    # Get the domain for the ACR based on the current Azure cloud

    AZURE_CLOUD=$(az cloud show --query name -o tsv)
    [[ "$AZURE_CLOUD" == "AzureUSGovernment" ]] && domain=".vault.usgovcloudapi.net" || domain=".vault.azure.net"

    echo "$domain"
}


login_container_registry() {
    # Login to a Container Registry instance (used for Zarf accessing private images)
    if [[ "$#" -ne 1 ]] || [[ -z "$1" ]]; then
        if [[ -n "$CONTAINER_REGISTRY_USER" ]] && [[ -n "$CONTAINER_REGISTRY_ACCESS_TOKEN" ]] && [[ -n "$CONTAINER_REGISTRY_URL" ]]; then
            # Login in with Env vars
            echo -e "\nDocker login to Container Registry: $CONTAINER_REGISTRY_URL"
            echo "$CONTAINER_REGISTRY_ACCESS_TOKEN" | docker login "$CONTAINER_REGISTRY_URL" -u "$CONTAINER_REGISTRY_USER" --password-stdin
        else
            echo "No container registry environment variables supplied"
            exit 1
        fi
    elif [[ -n "$1" ]]; then
        # Azure Container Registry
        echo -e "\nDocker login to ACR"
        local acr=$1

        CONTAINER_REGISTRY_URL="$acr$(get_acr_domain)"
        accessToken=$(az acr login --name "$acr" --expose-token --output tsv --query accessToken --only-show-errors)
        echo "$accessToken" | docker login "$CONTAINER_REGISTRY_URL" -u 00000000-0000-0000-0000-000000000000 --password-stdin
    else
        echo "Input must be in the format login_container_registry <acr_name> or with CONTAINER env vars"
        exit 1
    fi
}
