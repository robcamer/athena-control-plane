# Pipeline Secrets and Variables

***Github***

Name | Required(Y/N) | Description
--- | --- | ---
AZURE_CREDENTIALS | Y | Azure service principal credential json

***Gitlab***

Name | Required(Y/N) | Description
--- | --- | ---
ACCESS_TOKEN | Y | Group level access token
ARM_CLIENT_ID | Y | Azure service principal clientId
ARM_CLIENT_SECRET | Y | Azure service principal clientSecret
ARM_TENANT_ID | Y | Azure service principal tenantId
GITOPS_REPO_NAME | Y | Repo name of the gitops repo created

***Common***

Name | Required(Y/N) | Description | Default Value
--- | --- | --- | ---
DEPLOY_INFRA | N | Toggle flag for sample, non-production, Azure infrastructure creation that can be used to test out functionality | true
AZURE_CLOUD | N | The targeted azure cloud | AzureCloud
DEPLOY_ENV | N | The deployment env | dev
REGION | N | The targeted azure cloud region | eastus
SOPS_PUBLIC_KEY_SECRET_NAME | N | The name of the AKV secret containing the SOPS public key.  The recommended / default value is `sops-public-key`, but any desired name can be used.  This secret does not need to exist in AKV.  If it doesn't exist, it will be created with the name configured with this name when the pipeline runs.
SOPS_PRIVATE_KEY_SECRET_NAME | N | The name of the AKV secret containing the SOPS private key.  The recommended / default value is `sops-private-key`, but any desired name can be used.  This secret does not need to exist in AKV.  If it doesn't exist, it will be created with the name configured with this name when the pipeline runs.
SS_PUBLIC_KEY_SECRET_NAME | N | The name of the AKV secret containing the Sealed Secrets public key.  The recommended / default value is `ss-public-key`, but any desired name can be used.  This secret does not need to exist in AKV.  If it doesn't exist, it will be created with the name configured with this name when the pipeline runs.
SS_PRIVATE_KEY_SECRET_NAME | N | The name of the AKV secret containing the Sealed Secrets private key.  The recommended / default value is `ss-private-key`, but any desired name can be used.  This secret does not need to exist in AKV.  If it doesn't exist, it will be created with the name configured with this name when the pipeline runs.WORKLOAD_NAME | N | Name of the deployed workload | ntwkobsv
RESOURCE_GROUP_NAME | N | Name of the pre-created Resource Group | `rg-${WORKLOAD_NAME}-${DEPLOY_ENV}-${random_seed}`
AKS_NAME | N | Name of the pre-created Azure Kubernetes Service | `aks-${WORKLOAD_NAME}-${DEPLOY_ENV}-${random_seed}`
AKV_NAME | N | Name of the pre-created Azure Key Vault | `kv-${WORKLOAD_NAME}-${DEPLOY_ENV}-${random_seed}`
ACR_NAME | N | Name of the pre-created Azure Container registry | `cr${WORKLOAD_NAME}${DEPLOY_ENV}${random_seed}`
STORAGE_ACCOUNT | N | Name of the pre-created Storage Account | `st${WORKLOAD_NAME}${DEPLOY_ENV}${random_seed}`
VM_SIZE | N | Size of aks vms | standard_e2ds_v5

Note: changing DEPLOY_ENV or WORKLOAD_NAME will affect the generated resource names. Some resources do have naming restrictions.