#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used to generate sops public and private encryption keys
# * We only generate and store keys in AKV if both public and private key secrets are missing.
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

# Check if SOPS secrets exists
sops_public_key_exists=$(does_akv_secret_exist "$SOPS_PUBLIC_KEY_SECRET_NAME")
sops_private_key_exists=$(does_akv_secret_exist "$SOPS_PRIVATE_KEY_SECRET_NAME")

if [[ "$sops_public_key_exists" == "true" ]] && [[ "$sops_private_key_exists" == "true" ]]; then
    echo "SOPS keys already exist in AKV, skipping key generation..."
    exit 0
fi

if [[ "$sops_public_key_exists" != "$sops_private_key_exists" ]]; then
    echo "SOPS keys mismatched in AKV, sops_public_key_exists: $sops_public_key_exists, sops_private_key_exists: $sops_private_key_exists, stopping..."
    exit 1
fi

# Check if SS secrets exists
ss_public_key_exists=$(does_akv_secret_exist "$SS_PUBLIC_KEY_SECRET_NAME")
ss_private_key_exists=$(does_akv_secret_exist "$SS_PRIVATE_KEY_SECRET_NAME")

if [[ "$ss_public_key_exists" == "true" ]] && [[ "$ss_private_key_exists" == "true" ]]; then
    echo "SOPS keys already exist in AKV, skipping key generation..."
    exit 0
fi

if [[ "$ss_public_key_exists" != "$ss_private_key_exists" ]]; then
    echo "SOPS keys mismatched in AKV, ss_public_key_exists: $ss_public_key_exists, ss_private_key_exists: $ss_private_key_exists, stopping..."
    exit 1
fi

# Generate SOPS keys
wget -nv -O age-keygen.tar.gz https://dl.filippo.io/age/v1.0.0?for=linux/amd64
tar -xf age-keygen.tar.gz
age/age-keygen -o age.agekey
sops_public_key=$(grep 'public key:' age.agekey | awk '{print $4}')
sops_private_key=$(grep AGE-SECRET-KEY age.agekey)

# Store SOPS keys in AKV as a secret
az keyvault secret set --name "$SOPS_PUBLIC_KEY_SECRET_NAME" --vault-name "$KEYVAULT_NAME" --encoding base64 --value "$sops_public_key" >/dev/null
az keyvault secret set --name "$SOPS_PRIVATE_KEY_SECRET_NAME" --vault-name "$KEYVAULT_NAME" --encoding base64 --value "$sops_private_key" >/dev/null

# Generate SS keys
ss_public_key='tls.crt'
ss_private_key='tls.key'
openssl req -x509 -nodes -newkey rsa:4096 -keyout "$ss_private_key" -out "$ss_public_key" -subj "/CN=sealed-secret/O=sealed-secret"

# Store SS keys in AKV as a secret
az keyvault secret set --name "$SS_PRIVATE_KEY_SECRET_NAME" --vault-name "$KEYVAULT_NAME" --file "$ss_private_key" >/dev/null
az keyvault secret set --name "$SS_PUBLIC_KEY_SECRET_NAME" --vault-name "$KEYVAULT_NAME" --file "$ss_public_key" >/dev/null

# Generate cluster sealed secret yaml
yaml=$(kubectl -n infrastructure create secret tls sealed-secrets-key --cert="$ss_public_key" --key="$ss_private_key" -o yaml --dry-run=client | base64 -w 0)
az keyvault secret set --name sealed-secrets-key --vault-name "$KEYVAULT_NAME" --encoding base64 --value "$yaml" >/dev/null
