# Example Deployment - Network Observability Solution

The Mission Platform Ops Athena Control Plane Seed was originally developed to support the deployment of Crew Athena's Network Observability solution.  This example deployment is based on that solution.  Information about the four applications that comprise the Network Observability solution can be found at the links below.

- [PCAP Ingestor](https://github.com/microsoft/pcap-ingestor-app-seed)
- [PCAP Processor](https://github.com/microsoft/pcap-processor-app-seed)
- [Event Processor](https://github.com/microsoft/event-processor-app-seed)
- [Net Obs Stats Generator](https://github.com/microsoft/net-obs-stats-generator-app-seed)

## Deployment Flow

Azure infrastructure may be deployed automatically or manually to support testing solutions deployed with this seed.  In addition, either GitHub or GitLab may be used for source code management and CI/CD pipeline execution.  Instructions are provided for each approach.

The following flow will be used to deploy the solution.

1. Install Application Dependencies
1. Create a Service Principal
1. Deploy and Configure Azure Infrastructure
1. Deploy Network Observability Apps

## Install Application Dependencies

The following applications are required to deploy the Network Observability solution with this seed.  Install them now.

- [Coral CLI](https://github.com/microsoft/coral/blob/main/docs/platform-setup.md#install-coral-cli) - used by the Platform roles and continuous integration and continuous delivery (CI/CD) automation to accomplish tasks.
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/) - used to create and manage Azure resources.
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) - run commands against Kubernetes clusters.
- [Flux](https://fluxcd.io/flux/installation/) - manage one or more Kubernetes clusters.
- [GitHub CLI](https://github.com/cli/cli#installation) - GitHub on the command line.
- [yq](https://github.com/mikefarah/yq) - a lightweight and portable command-line YAML, JSON and XML processor.

## Create a Service Principal

The control-plane's CI/CD pipelines require a service principal to perform tasks like deploying infrastructure and managing SOPS keys.  The service principal will need to have `owner` permissions.  You will need your [subscription ID](https://learn.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id) to create a service principal.

If you want to automate the creation of the resource group with [Infrastructure Deployment](#infrastructure-deployment), the service principal will need `owner` permissions at the `subscription` level.  Use the commands below to create a service principal with this approach.

```bash
# Login to Azure
az login 

# Create Service Principal
az ad sp create-for-rbac --name <your service principal name> --role owner \
      --scopes /subscriptions/<your subscription id> \
      --sdk-auth

# To create at the subscription level for testing where it creates the RG (less secure)
az ad sp create-for-rbac --role owner \
      --scopes /subscriptions/<your subscription id> \
      --sdk-auth
```

If you don't want the service principal to have `owner` permissions at the `subscription` level, you must pre-create a resource group and give ownership over that specific resource group to the service principal using the commands below.  You can still use the instructions in [Infrastructure Deployment](#infrastructure-deployment) but must set the `RESOURCE_GROUP_NAME` variable/secret in the pipeline.

```bash
# Login to Azure
az login

# Create Resource Group
az group create --name <your resource group> --location <your resource group location>

# Create Service Principal
az ad sp create-for-rbac --name <your service principal name> --role owner \
      --scopes /subscriptions/<your subscription id>/resourceGroups/<your resource group> \
      --sdk-auth
```

The output from either approach will look similar to below.  Make sure the output is available for later steps.

```json
{
  "clientId": "<Your Client ID>",
  "clientSecret": "<Your Client Secret>",
  "subscriptionId": "<Your Subscription ID>",
  "tenantId": "<Your Tenant ID>",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.us",
  "resourceManagerEndpointUrl": "https://management.usgovcloudapi.net/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.usgovcloudapi.net:8443/",
  "galleryEndpointUrl": "https://gallery.usgovcloudapi.net/",
  "managementEndpointUrl": "https://management.core.usgovcloudapi.net/"
}
```

## Infrastructure Deployment

The required Azure infrastructure can be deployed automatically, with minimal manual configuration, by the pipeline or pre-created manually.  The names of any pre-created resources must be provided to the pipeline as variables/secrets.  A full list of variables and secrets is provided in [Pipeline Secrets and Variables](../learn_more/secrets_variables.md).  `DEPLOY_INFRA` may be set to `false` to skip all resource creation.

`AZURE_CLOUD` and `REGION` default to `AzureCloud` and `eastus` respectively. If the service principal was configured for a different Azure cloud or a different region is required, make sure to update the `AZURE_CLOUD` and `REGION` secrets/variables to valid values.  An example will be provided below.

If a resource group was manually created when the service principal was created (as [above](#create-a-service-principal)), the `RESOURCE_GROUP_NAME` variable must be set.  An example will be provided below.  In addition, the names of any pre-created resources must be provided as secrets/variables.

After the infrastructure deployment, the required Azure resources will be deployed. A state file will be generated in the infrastructure folder containing all of the resources relevant to the control-plane.  The automation will also create the cluster YAML and bootstrap Flux in to the Azure Kubernetes Service cluster once it is created.

First, we'll create the control-plane and GitOps repos for the Network Observability solution from this seed.  Use the appropriate instructions for your source code/pipeline solution, either GitHub or GitLab.  It may be helpful to execute the commands in your IDE's terminal so that the environment variables persist after you clone the control-plane created by the Coral CLI.

***

***GitHub***

You will need a GitHub Personal Access Token with `repo`, `workflow`, and `packages` scopes.  Information on creating a GitHub PAT are available [here](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token).  You may need to configure single sign-on for the PAT if your organization requires it.

```bash
export GITHUB_TOKEN="<Personal Access Token>"
export GITHUB_OWNER="<GitHub User>"
export GITHUB_USER="<GitHub User>"
export repo_prefix=test01

coral init github \
  --control-plane-seed microsoft/network-observability-control-plane-seed \
  --control-plane $GITHUB_OWNER/$repo_prefix-control-plane \
  --gitops $GITHUB_OWNER/$repo_prefix-cluster-gitops
```

***

***GitLab***

In order to use this seed with GitLab, the Premium SKU or higher is required for repo templates. You will need to hard fork repos from GitHub into a GitLab group (or sub-group) wtihin your GitLab organization. The control plane seed and app seed repos will need to be configured as group-level templates.

You will need a GitLab Personal Access Token (PAT) with `api`, `read_repository` and `write_repository` scopes.  You can find more information at the GitLab [docs](https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html).

```bash
export GITLAB_TOKEN="<GitLab PAT>"
export repo_prefix=test01

# Group IDs are available in the GitLab UI on the group home page, next to the group name.
coral init gitlab \
  --gitlab-host <Your GitLab Host> \
  --control-plane-seed-group-id <Your Control Plane Seed Group ID> \
  --control-plane-seed <Network Observabilility Control Plane Seed Repo> \
  --target-group-id <Your Target Group ID> \
  --control-plane $repo_prefix-control-plane \
  --gitops $repo_prefix-cluster-gitops
```

***

Coral created two repos, one for the control plane and another that serves as the cluster GitOps repo.

The initial pipeline run in the control plane will fail because we have not set the required secrets/variables.  Remember to provide the names of any resources you have pre-created as with the `RESOURCE_GROUP_NAME` example provided below.

***

***GitHub***
  
```bash
  cat << 'EOF' > .envcp
  AZURE_CLOUD=AzureUSGovernment                  # Not required.  Set if not using AzureCloud.
  REGION=usgovvirginia                           # Not required.  Set if not using eastus.
  RESOURCE_GROUP_NAME=my-resource-group          # Not required.  Set if resource group was pre-created.
  AZURE_CREDENTIALS={<SERVICE PRINCIPAL JSON>}   # Required. Paste the entire JSON output from the service principal command without line breaks.
  EOF
  
  # Set the required secrets in the control plane repo.
  gh secret set -f .envcp -R $GITHUB_OWNER/$repo_prefix-control-plane
```

***

***GitLab***

Create the following list of required variables in the control-plane repo that was created in your GitLab instance. Variables can be created using either the [GitLab UI](https://docs.gitlab.com/ee/ci/variables/#for-a-project) or by using the [GitLab REST API](https://docs.gitlab.com/ee/api/project_level_variables.html#create-a-variable).

Name | Description
--- | ---
ACCESS_TOKEN | Group Level Access Token
ARM_CLIENT_ID | Azure Service Principal clientID
ARM_CLIENT_SECRET | Azure Service Principal clientSecret
ARM_TENANT_ID | Azure Service Principal tenantID
GITOPS_REPO_NAME | Name of the created GitOps Repo

***

If any pipelines are still running and haven't failed, cancel them now in the GitHub or GitLab UI.

With the secrets now set, we can re-run the control plane pipeline in the GitHub or GitLab UI to execute the [deployment flow](../../README.md#overview).  The pipeline will take several minutes (~10 in GitHub, longer if packaging with Zarf) to complete the first time it is successfully run.

After the pipeline successfully runs, it will commit changes to both the control plane and GitOps repos.

Connect to the Azure Kubernetes Service cluster and confirm the resources have been created as below.

```bash
# Set Subscription
az account set --subscription <Subscription ID>

# Get AKS Credentials
az aks get-credentials --resource-group <Resource Group Name> --name <AKS Name>

# List all deployments in all namespaces
kubectl get deployments --all-namespaces=true
```

The output of the kubectl command will look similar to the output below.

```bash
NAMESPACE        NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
flux-system      helm-controller                            1/1     1            1           24m
flux-system      kustomize-controller                       1/1     1            1           24m
flux-system      notification-controller                    1/1     1            1           24m
flux-system      source-controller                          1/1     1            1           24m
infrastructure   azure-sql-edge                             1/1     1            1           23m
infrastructure   elasticsearch-metrics                      1/1     1            1           21m
infrastructure   istio-gateway                              1/1     1            1           22m
infrastructure   istiod                                     1/1     1            1           23m
infrastructure   kiali                                      1/1     1            1           20m
infrastructure   kiali-kiali-operator                       1/1     1            1           21m
infrastructure   kibana                                     1/1     1            1           21m
infrastructure   kube-prometheus-stack-grafana              1/1     1            1           23m
infrastructure   kube-prometheus-stack-kube-state-metrics   1/1     1            1           23m
infrastructure   kube-prometheus-stack-operator             1/1     1            1           23m
infrastructure   zipkin                                     1/1     1            1           23m
kube-system      coredns                                    2/2     2            2           26m
kube-system      coredns-autoscaler                         1/1     1            1           26m
kube-system      konnectivity-agent                         2/2     2            2           26m
kube-system      metrics-server                             2/2     2            2           26m
```

## Deploy Network Observability Apps

Now that the base infrastructure is deployed, we can deploy the apps that comprise the Network Observability solution.

First, provide yourself access to the Azure Key Vault as in [Assign a Key Vault access policy](https://learn.microsoft.com/en-us/azure/key-vault/general/assign-access-policy?tabs=azure-portal).  "Select All" permissions listed under "Secret permissions".

Ensure that `CoralAppInit.sh` is run from the control-plane repo's root as is shown below. 

### Canary App Init

To have this script render canary `app.yaml` content, add the `canary` parameter to the end of the command (GitHub example), alternatively, remove that parameter for a regular deployment app.yaml (GitLab example).

***

***GitHub***

```bash
repo_prefix=contoso

# Create environment variables for the NuGet repository.  Required for the apps.
export NUGET_PLATFORM_URL=https://nuget.pkg.github.com/<your-org>/index.json  
export NUGET_SOURCE_URL=https://api.nuget.org/v3/index.json 

# Clone the control-plane created earlier to your local environment.
gh repo clone $GITHUB_OWNER/$repo_prefix-control-plane
cd $repo_prefix-control-plane

# Run the script for each of the Network Observability solution apps.
# Include a 4th parameter "canary" for generating canary app.yaml
./scripts/pipeline/coralAppInit.sh istio-service crew-athena-org/pcap-ingestor-app-seed  $GITHUB_OWNER/$repo_prefix-pcap-ingestor canary
./scripts/pipeline/coralAppInit.sh istio-service crew-athena-org/pcap-processor-app-seed $GITHUB_OWNER/$repo_prefix-pcap-processor canary
./scripts/pipeline/coralAppInit.sh istio-service crew-athena-org/event-processor-app-seed $GITHUB_OWNER/$repo_prefix-event-processor canary
./scripts/pipeline/coralAppInit.sh istio-service crew-athena-org/net-obs-stats-generator-app-seed $GITHUB_OWNER/$repo_prefix-netobs-statsgen canary

# Re-run any script if the secrets fail to push (due to a GitHub API error).

# If an app does not show up in the GitOps repo, delete the application repo and run the script again (usually due to an intermittent connection error).
```

***

***GitLab***

```bash
repo_prefix=contoso

# Create environment variables for the NuGet repository.  Required for the apps.
export NUGET_PLATFORM_URL=https://<Your GitLab Instance>/api/v4/groups/<Your Group ID>/-/packages/nuget/index.json
export NUGET_SOURCE_URL=https://api.nuget.org/v3/index.json
export GITLAB_OWNER="<Your GitLab Owner>" 

# Clone the control-plane created earlier to your local environment.
git clone <Your Control Plane Repo>
cd <Your Control Plane Repo>

# Run the script for each of the Network Observability solution apps.
./scripts/pipeline/coralAppInit.sh istio-service <PCAP Ingestor App Seed>  $GITLAB_OWNER/$repo_prefix-pcap-ingestor
./scripts/pipeline/coralAppInit.sh istio-service <PCAP Processor App Seed> $GITLAB_OWNER/$repo_prefix-pcap-processor
./scripts/pipeline/coralAppInit.sh istio-service <Event Processor App Seed> $GITLAB_OWNER/$repo_prefix-event-processor
./scripts/pipeline/coralAppInit.sh istio-service <Net Obs Stats Generator App Seed> $GITLAB_OWNER/$repo_prefix-netobs-statsgen
```

***

`CoralAppInit.sh` will return YAML that needs to be committed to the app repo it created.  Replace the content in each apps' `app.yaml` file with the output returned from `CoralAppInit.sh` and commit the changes to `main`.

Each of the apps has a separate pipeline that will fail on its initial run because the newly created app repos do not have permissions for the NuGet package repository.  If using GitHub, provide access to the required packages by following [GitHub Actions access for packages scoped to organizations](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#github-actions-access-for-packages-scoped-to-organizations).  Re-run the pipeline for each app once the repos have access to the required NuGet packages.

The app scripts you ran above created YAML files with encrypted secrets that must be pushed to your control-plane repo.  This push to `main` will start the pipeline to ensure the app secrets are available to the cluster.  Commit and push the control-plane repo and ensure the pipeline completes as expected.

The app pods will now start and are ready for ingestion after initialization.
