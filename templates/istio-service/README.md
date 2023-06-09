# Istio Service

**Author:** Marshall Bentley
**Date:** 11/29/2022

This template exposes parameters needed for App Teams to deploy an application which is integrated into the Istio service mesh.

## Configuration

Applications will be integrated into the Istio service mesh and will automatically have an Envoy proxy sidecar installed in the pod alongside the application.  A service is created for the application with the name set to the value of the `versionIndependentName` parameter.

This template provides the option to configure the application as a canary deployment by setting the parameter `canary: true`.  Custom environment variables can be configured using the `config` parameter.

## Required Values

These values are required and should be provided regardless of the value of the `canary` parameter:

- name - The application's name.
- versionIndependentName - The application's name, independent of versioning.  The value should be the same for all deployed versions of an app.  For example, if you deploy two versions of the same app, `app-v1` and `app-v2`, the version independent name might be `app`.  This parameter is used to refer to all versions of an application when configuring service mesh routing.
- version - The application's version.
- image - The image specification including tag of the container image to use.
- port - The port on the container where the app can be accessed

## Optional Values

These parameters are optional and should only be provided if needed / used:

- imagePullSecret: Boolean variable which indicates whether an imagePullSecret should be configured.  If enabled, these secrets should be configured by following instructions in the [Configuring ImagePullSecrets section](#configuring-imagepullsecrets).
- config: Environment variables to set on the deployment listed as a single string.  The format is shown in the examples section.
- requestsMemory: Amount of memory to allocate to the application. Defaults to 256Mi.
- limitsMemory: Max limit of the amount of memory to allocate to the application. Defaults to 1Gi.
- requestsCPU: Number of request Kubernetes processing units. Defaults to 125m.
- limitsCPU: Max limit of the number of request Kubernetes processing units. Defaults to 1000m.

## Canary Values

In addition to the standard required values, these values are required for canary deployments where `canary: true`:

- canary - A boolean flag which which set to true, indicates this version as a canary deployment.
- version - The canary application's version.  For example: `version: "v2"`.
- currentVersion - The original application's version.  For example: `version: "v1"`.
- weight - The percentage of traffic that should be directed to this application and version.
- currentWeight - The percentage of traffic that should be directed to the original application and version.  For example, if this canary version is `weight: 25`, currentWeight might be `currentWeight: 75`.  This would configure 75% of traffic to the current version and 25% to the canary.

## Configuring Secrets

This template supports injecting user defined secrets into the application deployment using placeholder for secret yaml files stored in control plane.  Secrets are created as part of application / deployment pipline.  To enable and configure secrets, follow the steps described below.

### Application Secrets Conventions

### Create secret Yaml Files:

Create a secret yaml file in the control-plane under `templates/istio-service/deploy/` following these conventions:

1. If the secret is an application secret, the secret yaml file should be in the format `<application name>-secrets.enc.yaml`.  For example, if the app.yaml defines the application's name as `app-v1`, the placeholder file should be named `templates/istio-service/deploy/app-v1.enc.yaml`. If there are multiple versions, a secret is required per version e.g. `app-v1.enc.yaml` and `app-v2.enc.yaml`.
2. If the secret is an imagePullSecret, the secret yaml file should be in the format `<application name>-image-pull-secret.enc.yaml` suffix.  For example, if the app.yaml defines the application's name as `app-v1`, the placeholder file should be named `templates/istio-service/deploy/app-v1-image-pull-secret.enc.yaml`.
3. When deploying multiple versions of an application or utilizing canary deployments, a secret yaml file should be created for each version.  Each yaml file should use the value of the name parameter for that deployment defined in app.yaml.  For example, if an app.yaml defines deployments of both `app-v1` and `app-v2`, secret files `templates/istio-service/deploy/app-v1-secrets.enc.yaml` and `templates/istio-service/deploy/app-v2-secrets.enc.yaml` should be created.
4. Secret tags example `<<<db-connection-string>>>` are used to create AKV secrets in the next step.
5. When deploying multiple versions of an application or utilizing canary deployments, the secrets tags should be unique.

> **Note**  The secret names/tags have global scope, Platform team should review/ensure the incoming app secrets to make sure they are unique, so that they are not referencing other app secrets.

For example, a secret file for the application `app-v1` might look like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: "{{name}}-secrets"
  namespace: "{{coral.workspace}}-{{coral.app}}"
data:
  DB_CONNECTION_STRING: <<<db-connection-string>>>
  RABBITMQ_PASSWORD: <<<rabbitmq-password>>>
  azurestorageaccountkey: <<<azurestorageaccountkey>>>
  azurestorageaccountname: <<<azurestorageaccountname>>>
```

When the CI / CD pipeline runs, the raw secret value will be retrieved from AKV, encrypted, copied into these files in GitOps and deployed.

### Create Azure Key Vault Secrets

> **Note**  This is handled by pipeline currently, follow the below steps in case if you would like to create the secrets manually, and pipline will use these secrets

Create secrets and store them in AKV.  Several conventions must be followed when creating secret files:

1. For every secret tag created in the above secret yaml file, create a AKV secret. For example: For `<<<db-connection-string>>>` --> AKV secret name: `db-connection-string``, AKV secret name: `<your db pw>`
2. The AKV secret name has to match the tag names from yaml files.
3. The AKV secret value must be base64 encoded into a single line string (no newlines) using the steps [here](../../docs/design-decisions/secret-management.md#base64-encoding-secrets)

### Configuring ImagePullSecrets

Before using this template, determine whether your application requires credentials to pull down its image from your container registry.  If it doesn't, you can skip this section.

In order to deploy your application, an imagePullSecret will need to be created to authenticate to the container registry.  Create your secret and store it in a yaml file, the following is an example creating an imagePullSecret for the GitHub container registry:

```bash
kubectl create secret docker-registry --dry-run=client '{{name}}-image-pull-secret' \
  --namespace='{{coral.workspace}}-{{coral.app}}' \
  --docker-server=ghcr.io \
  --docker-username='testuser' \
  --docker-password='test-pw' \
  --docker-email=testemail -o yaml > image-pull-secret.yaml
```

Next, follow the imagePullSecret version of the steps in the [Configuring Secrets section](#configuring-secrets) to add your ImagePullSecret to AKV and automatically encrypt and deploy it using the CI / CD pipeline.

### Dedicated Application Secrets / Canary Secrets

This template provides a dedicated secret for each application using it.  Secrets are not shared among multiple applications using the same template.  This also applies to multiple versions of the same application (such as when using canary deployments).  When configuring secrets, applications implementing canary deployments should create an empty / placeholder file for both current and canary versions.

## Examples

The following is an example configuring two versions of the `dotnet-app` to be deployed, `app-v1` and `app-v2`.  In this example, `app-v1` is the current version and is deployed from the main branch.  `app-v1` is the canary version and is deployed from the feature branch.  75% of traffic is routed to `app-v1` while 25% is routed to the canary deployment, `app-v2`.

```yaml
template: istio-service
deployments:
  current:
    target: current
    clusters: 1
    values:
      name: app-v1
      versionIndependentName: dotnet-app
      version: "v1"
      image: ghcr.io/testuser/app-v1:main
      port: 5000
      imagePullSecret: true
      config: "VALIDATION_DIRECTORY: '/var/data/validation'\n  RABBITMQ_HOSTNAME: 'rabbitmq'\n  RABBITMQ_USERNAME: 'rabbit'"
  canary:
    target: canary
    clusters: 1
    values:
      canary: true
      name: app-v2
      versionIndependentName: dotnet-app
      version: "v2"
      weight: 25
      currentVersion: "v1"
      currentWeight: 75
      image: ghcr.io/testuser/app-v1:feature
      port: 5000
      imagePullSecret: true
      config: "VALIDATION_DIRECTORY: '/var/data/validation'\n  RABBITMQ_HOSTNAME: 'rabbitmq'\n  RABBITMQ_USERNAME: 'rabbit'"
```
