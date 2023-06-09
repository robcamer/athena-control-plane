#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used for encrypting the secrets for SOPS as well as SEALED secrets
# * Reads the secrets from KeyValut and encrypts them
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

ss=false
encryption_secret_name="$SOPS_PUBLIC_KEY_SECRET_NAME"
no_secrets_error_msg="No secrets found to encrypt, stopping..."

if [[ "$#" -gt 0 ]] && [[ "$1" == "ss" ]]; then
    ss=true
    encryption_secret_name="$SS_PUBLIC_KEY_SECRET_NAME"
fi

if [[ -z "$encryption_secret_name" ]]; then
    echo "Encryption secret name not defined, stopping..."
    exit 1
fi

encryption_key=$(get_akv_secret "$encryption_secret_name")

if [[ -z "$encryption_key" ]]; then
    echo "Encryption key not found, stopping..."
    exit 1
else
    [[ "$ss" = true ]] && az keyvault secret show --name "$encryption_secret_name" --vault-name "$KEYVAULT_NAME" --query 'value' -o tsv >tls.crt
fi

if [[ "$ss" == "true" ]]; then
    search_path='controlplane/zarf'
else
    search_path='gitops'
fi

mapfile -t secret_files < <(find "$search_path" -iname '*.enc.yaml')

# Perform encryption
for secret_file in "${secret_files[@]}"; do
    if [[ "$ss" == "true" ]] && [[ $secret_file == "controlplane/zarf"* ]] && [[ $(grep -c 'kind: Secret' <"$secret_file") -eq 1 ]]; then
        # Encrypt Zarf files with Sealed Secrets (only works for Secrets)
        echo "Sealed Secrets encryption: $secret_file"

        output=$(kubeseal <"$secret_file" --format yaml --cert tls.crt)
        echo "$output" >"$secret_file"

    elif [[ "$ss" == "false" ]] && [[ $secret_file == "gitops"* ]]; then
        # Encrypt GitOps files with SOPS
        echo "SOPS encryption: $secret_file"

        output=$(sops --encrypt --verbose --age "$encryption_key" --encrypted-regex '^(data|stringData)$' "$secret_file")
        echo "$output" >"$secret_file"
    fi
done
