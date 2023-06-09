#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used populate secrets files on Key Vault
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

# Get Azure values
readonly state_file=controlplane/infrastructure/state
if [[ -f $state_file ]]; then
    state_kv=$(awk '/KEYVAULT_NAME/  { print $2 }' $state_file)
fi

readonly akv_name=${AKV_NAME:-${state_kv}}
akv_url="https://$akv_name$(get_akv_domain)"

echo -e "\nReplacing placeholders with secrets found in AKV $akv_url"

# Get all unique list of secrets
mapfile -t unique_secrets < <(find gitops -iname "*.enc.yaml" -exec grep '<<<.*>>>' {} \; | sort -u | sed 's/.*<<<//g' | sed 's/>>>//g')

if [[ ${#unique_secrets[@]} -eq 0 ]]; then
    echo "No secrets found to encrypt, stopping..."
    exit 0
fi

# Get matching secrets from AKV
for secret in "${unique_secrets[@]}"; do
    akv_secret_value=$(get_akv_secret "$secret")

    if [[ -z "$akv_secret_value" ]]; then
        echo "No AKV secret matching $secret, stopping..."
        exit 1
    fi

    # Get all enc secret files (now updated by Coral) which contain the secret
    mapfile -t secret_files < <(grep --include=\*.enc.yaml -rnw gitops controlplane/zarf -e "<<<$secret>>>" | awk -F':' '{ print $1 }')

    # Write AKV secret value to map
    echo "Populating secret: $secret"
    for secret_file in "${secret_files[@]}"; do
        echo " - $secret_file"
        if [[ $(grep -c 'kind: Secret' <"$secret_file") -eq 1 ]]; then
            sed -i "s/<<<$secret>>>/$akv_secret_value/g" "$secret_file"
        else
            # configMaps
            sed -i "s|<<<$secret>>>|$(echo "$akv_secret_value" | base64 --decode)|g" "$secret_file"
        fi
    done
done
