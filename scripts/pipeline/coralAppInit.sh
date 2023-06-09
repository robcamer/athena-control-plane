#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Local run Coral App Init for GitHub
# * Pipeline and AKV secrets creation
# * Note: Update app.yaml manually after!
# *
# * Required environment variables, the control panel's state file provides the rest
# * Can be created in ~/.env to be reused centrally
# *
#   * Name: NUGET_PLATFORM_URL
#   * Value: Nuget platform e.g. https://nuget.pkg.github.com/<org>/index.json
#   * Name: NUGET_SOURCE_URL
#   * Value: Nuget source e.g. https://api.nuget.org/v3/index.json
#   * Name: GITHUB_USER
#   * Value: Provides the PACKAGE_REGISTRY_USERNAME
#   * Name: GITHUB_TOKEN
#   * Value: Provides the PACKAGE_REGISTRY_PASSWORD
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh
if [[ -f ~/.env ]]; then
    set -o allexport; source ~/.env; set +o allexport
fi

# Get authorization
if [[ -z "$GITHUB_TOKEN" ]] || [[ -z "$GITHUB_USER" ]]; then
    echo -e "Error: No GITHUB_USER or GITHUB_TOKEN env variables!" && exit 1
fi

# Get input values
if [[ -z ${1:-} ]]; then
    echo -e "Error: No template name provided!\n e.g. istio-service" && exit 1
else
    readonly app_template=$1
fi

if [[ -z ${2:-} ]]; then
    echo -e "Error: No app seed name provided!\n e.g. microsoft/coral-seed-dotnet-api" && exit 1
else
    readonly app_seed=$2
fi

if [[ -z ${3:-} ]]; then
    echo -e "Error: No app name provided!\n e.g. contoso/custom-dotnet-api" && exit 1
else
    readonly app_repo=$3
    app_name=$(echo "$app_repo" | cut -d/ -f2-)
    readonly app_name
fi

if [[ -z ${4:-} ]]; then
    readonly service_mesh="true"
else
    readonly service_mesh="false"
fi

# Get Azure values
readonly state_file=infrastructure/state
if [[ -f $state_file ]]; then
    state_rg=$(awk '/RESOURCE_GROUP_NAME/  { print $2 }' $state_file)
    state_kv=$(awk '/KEYVAULT_NAME/  { print $2 }' $state_file)
    state_staccnt=$(awk '/STORAGE_ACCOUNT_NAME/  { print $2 }' $state_file)
    state_acr=$(awk '/ACR_NAME/  { print $2 }' $state_file)
fi

readonly resource_group_name=${RESOURCE_GROUP_NAME:-${state_rg}}
readonly staccnt_name=${STORAGE_ACCOUNT:-${state_staccnt}}
readonly acr_name=${ACR_NAME:-${state_acr}}
readonly akv_name=${AKV_NAME:-${state_kv}}
export KEYVAULT_NAME="$akv_name"

acr_key=$(az acr credential show --name "${acr_name}" --query passwords[0].value)
if [[ -z ${acr_key:-} ]]; then
    echo "Error: Azure Container Registry key not available, please enable the admin user!" && exit 1
fi

# set cloud specific vars
AZURE_CLOUD=$(az cloud show --query name -o tsv)
readonly AZURE_CLOUD
case $AZURE_CLOUD in
"AzureUSGovernment")
    readonly cr_url="${acr_name}.azurecr.us"
    ;;
*)
    readonly cr_url="${acr_name}.azurecr.io"
    ;;
esac

# Get Coral values
repo=$(yq '.spec.repo' templates/"${app_template}".yaml)
readonly repo
control_plane="$(echo "$repo" | grep / | cut -d/ -f4-)"
readonly control_plane
readonly env=${DEPLOY_ENV:-"dev"}
readonly workspace=${WORKSPACE:-"ghdev"}

# Run app init
app_init="coral app init github \
--control-plane $control_plane \
--starter-application-seed $app_seed \
--starter-application $app_repo \
--environment-targets $env \
--workspace $workspace \
& wait"

# Create the repos with app init if they do not exist
if [[ $(gh repo list "$GITHUB_OWNER" --json name -q '.[].name' | grep -c "$app_name") -eq 0 ]]; then
    echo -e "Running Coral app init...\n$app_init"
    eval "$app_init"
else
    echo "Coral app init run previously..."
fi
echo -e "Verify app registration: https://github.com/$control_plane/tree/main/applications/ghdev/ApplicationRegistrations\n"

# Add secret .enc placeholder file to template deployment
readonly secret_name="$app_name-secrets"

# Add secrets to AKV
echo "Adding app secrets to AKV..."

rabbit_password="$(get_akv_secret rabbitmq-password | base64 --decode)"
sql_password="$(get_akv_secret azure-sql-edge-password | base64 --decode)"

if [[ -z "$rabbit_password" ]]; then
    echo "Fetching AKS supplied password"
    rabbit_password=$(kubectl get secret rabbitmq -n infrastructure -o jsonpath="{.data.rabbitmq-password}")
    if [[ -n "$rabbit_password" ]]; then set_akv_secret "rabbitmq-password" "$rabbit_password"; fi
fi

if [[ -z "$sql_password" ]]; then
    echo "Fetching AKS supplied password"
    sql_password=$(kubectl get secret azure-sql-edge-secrets -n infrastructure -o jsonpath="{.data.sql-password}")
    if [[ -n "$sql_password" ]]; then set_akv_secret "azure-sql-edge-password" "$sql_password"; fi
fi

if [[ -n "$rabbit_password" ]] && [[ -n "$sql_password" ]] && [[ -n "$acr_name" ]] && [[ -n "$acr_key" ]]; then
    sql_connstr="SERVER=azure-sql-edge-service.infrastructure;TRUSTSERVERCERTIFICATE=true;UID=sa;PASSWORD=$sql_password;"
    storage_key="$(az storage account keys list -g "$resource_group_name" -n "$staccnt_name" --query [0].value -o tsv)"

    # Adding app secret
    echo "Generating secret file (commit to control plane after the app image pipeline completes)"
    secret_file="templates/$app_template/deploy/$secret_name.enc.yaml"
    kubectl create secret generic '{{name}}-secrets' -n '{{coral.workspace}}-{{coral.app}}' \
        --from-literal=azurestorageaccountkey='<<<>>>' \
        --from-literal=azurestorageaccountname='<<<>>>' \
        --from-literal=RABBITMQ_PASSWORD='<<<>>>' \
        --from-literal=DB_CONNECTION_STRING='<<<>>>' \
        --dry-run=client -o yaml \
        | yq '(.data.azurestorageaccountkey) = "<<<azurestorageaccountkey>>>"' \
        | yq '(.data.azurestorageaccountname) = "<<<azurestorageaccountname>>>"' \
        | yq '(.data.RABBITMQ_PASSWORD) = "<<<rabbitmq-password>>>"' \
        | yq '(.data.DB_CONNECTION_STRING) = "<<<db-connection-string>>>"' \
        | yq 'del(.metadata.creationTimestamp)' \
        >"$secret_file"

    echo "Saving secrets to AKV"
    if [[ $(does_akv_secret_exist azurestorageaccountkey) == "false" ]]; then set_akv_secret azurestorageaccountkey "$(base64_encode_one_line "$storage_key")"; fi
    if [[ $(does_akv_secret_exist azurestorageaccountname) == "false" ]]; then set_akv_secret azurestorageaccountname "$(base64_encode_one_line "$state_staccnt")"; fi
    if [[ $(does_akv_secret_exist db-connection-string) == "false" ]]; then set_akv_secret db-connection-string "$(base64_encode_one_line "$sql_connstr")"; fi
else
    echo "Error: App secret dependencies not found"
    exit 1
fi

# Set app repo secrets
echo -e "\nUpdating pipeline variables..."
env_file=".env_${app_repo////\-}"
readonly env_file
rm -f "$env_file"

{
    echo "CONTAINER_REGISTRY_URL=$cr_url"
    echo "CONTAINER_REGISTRY_ACCESS_TOKEN=$acr_key"
    echo "CONTAINER_REGISTRY_USER=$acr_name"
    echo "NUGET_PLATFORM_URL=$NUGET_PLATFORM_URL"
    echo "NUGET_SOURCE_URL=$NUGET_SOURCE_URL"
    echo "PACKAGE_REGISTRY_USERNAME=$GITHUB_USER"
    echo "PACKAGE_REGISTRY_PASSWORD=$GITHUB_TOKEN"
} >>"$env_file"

echo -e "/ngh secret set -f $env_file -R $app_repo # re-run this if set errors occur /n "
gh secret set -f "$env_file" -R "$app_repo"

[[ "$AZURE_CLOUD" == "AzureUSGovernment" ]] && acr_url=$acr_name.azurecr.us || acr_url=$acr_name.azurecr.io

echo ""
echo "Done! Please edit the app.yaml file"
echo "https://github.com/$app_repo/blob/main/app.yaml"
echo ""

if [[ "$service_mesh" == "true" ]]; then
    printf "%s" "template: istio-service
deployments:
  dev:
    target: dev
    clusters: 1
    values:
      name: $app_name
      versionIndependentName: dotnet-app
      version: \"v1\"
      image: $acr_url/$app_repo:main
      port: 5000
      requestsMemory: 256Mi
      requestsCPU: 125m
      limitsCPU: 1000m
      limitsMemory: 1Gi
      config: \"ERROR_DIRECTORY: '/var/data/error'\n  VALIDATION_DIRECTORY: '/var/data/validation'\n  VALIDATED_DIRECTORY: '/var/data/validated'\n  PCAP_PROCESS_QUEUE: 'pcap_queue'\n  RABBITMQ_HOSTNAME: 'rabbitmq.infrastructure.svc.cluster.local'\n  RABBITMQ_USERNAME: 'user'\n  RABBITMQ_PORT: '5672'\n  EVENT_META_DATA_DIRECTORY: '/var/data/metadata'\n  EVENTDATA_PROCESS_QUEUE: 'event_queue'\"
"
else
    printf "%s" "template: istio-service
deployments:
  current:
    target: dev
    clusters: 1
    values:
      name: $app_name-v1
      versionIndependentName: dotnet-app
      version: \"v1\"
      image: $acr_url/$app_repo:main
      port: 5000
      requestsMemory: 256Mi
      requestsCPU: 125m
      limitsCPU: 1000m
      limitsMemory: 1Gi
      config: \"ERROR_DIRECTORY: '/var/data/error'\n  VALIDATION_DIRECTORY: '/var/data/validation'\n  VALIDATED_DIRECTORY: '/var/data/validated'\n  PCAP_PROCESS_QUEUE: 'pcap_queue'\n  RABBITMQ_HOSTNAME: 'rabbitmq.infrastructure.svc.cluster.local'\n  RABBITMQ_USERNAME: 'user'\n  RABBITMQ_PORT: '5672'\n  EVENT_META_DATA_DIRECTORY: '/var/data/metadata'\n  EVENTDATA_PROCESS_QUEUE: 'event_queue'\"
  canary:
    target: dev
    clusters: 1
    values:
      canary: true
      weight: 10
      currentVersion: \"v1\"
      currentWeight: 90 
      name: $app_name-v2
      versionIndependentName: dotnet-app
      version: \"v2\"
      image: $acr_url/$app_repo:main # update tag to match new branch name for canary version
      port: 5000
      requestsMemory: 256Mi
      requestsCPU: 125m
      limitsCPU: 1000m
      limitsMemory: 1Gi
      config: \"ERROR_DIRECTORY: '/var/data/error'\n  VALIDATION_DIRECTORY: '/var/data/validation'\n  VALIDATED_DIRECTORY: '/var/data/validated'\n  PCAP_PROCESS_QUEUE: 'pcap_queue'\n  RABBITMQ_HOSTNAME: 'rabbitmq.infrastructure.svc.cluster.local'\n  RABBITMQ_USERNAME: 'user'\n  RABBITMQ_PORT: '5672'\n  EVENT_META_DATA_DIRECTORY: '/var/data/metadata'\n  EVENTDATA_PROCESS_QUEUE: 'event_queue'\"
"
fi
echo ""
echo "$(basename "$0") done!"
