# Secret Management

**Author:** Marshall Bentley, Swetha Anand
**Date:** 10/25/2022

## Context and Scope

This control plane follows GitOps principles which rely on infrastructure as code (IaC) and elevate source / version control as the single source of truth.  Ideally, all resources are defined in the source code repository and commits are used as the driver of change.  This philosophy begins to break down however, when it comes to secret management as secrets cannot traditionally be stored in source control without being compromised.  We are able to overcome this issue by encrypting secrets and storing the encrypted files in source control.  Doing this preserves alignment with GitOps as all resources, including secrets, are maintained in source control.

The following secret management documentation is specific to the Cloud Native control-plane implementation which can operate in connected cloud, edge, disconnected and air-gapped environments.

## Mozilla SOPS

Mozilla [SOPS](https://github.com/mozilla/sops) (Secrets OPerationS) is a command line application that supports encrypting and decrypting files as well as specific values within those files.  We use it, along with the [AGE](https://github.com/FiloSottile/age) encryption library, to encrypt secret files before placing them under source control as well to decrypt them after they're deployed to the Kubernetes cluster.

## SOPS and Flux

This control-plane configures Flux to use SOPS as its decryption provider.  Doing this allows Flux to automatically detect and decrypt encrypted secrets when deployed to the cluster.  The following config is only shown for understanding.  It is applied and ready to use out of the box.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

## Bitnami Sealed Secrets

The disconnected deployment scenario using Zarf does not include Flux.  Since SOPS depends on Flux to provide automatic in-cluster decryption functionality, the disconnected scenario instead uses Bitnami Sealed Secrets for secret management.  Sealed Secrets (SS) and SOPS have similar workflows.  Both use asymmetric certs / keys to provide encryption functionality, provide a command line tool which performs file encryption and perform automatic secret in-cluster decryption.  The main difference is SOPS depends on Flux for in-cluster decryption, while SS uses a controller pod installed in the cluster using a [Helm chart](../../manifests/sealed-secrets).

## Automatic Secret Encryption using Azure Key Vault and CI / CD Pipeline

### Overview / Workflow

This control-plane uses Azure Key Vault (AKV) to store and manage all encryption / decryption keys and secret / sensitive values.  Pipeline access to AKV is obtained via Service Principal credentials stored in the `AZURE_CREDENTIALS` pipeline secret variable.  This approach establishes conventions which must be followed to function correctly.  After creating AKV, a Service Principal with correct permissions and entering credentials into the `AZURE_CREDENTIALS` pipeline secret variable, the high level automatic encryption workflow is as follows:

1. Secret yaml files are created and committed where needed in the control-plane. Files for the App secrets should be named following the convention `<app name>-secrets.enc.yaml`, for example `myapp-secrets.enc.yaml`. Files for the Dial tone secrets can be named following the convention `<any name>.enc.yaml`, for example `mysecret.enc.yaml` Example for the placeholder secret file:

    ```yaml
    apiVersion: v1
    data:
      DB_CONNECTION_STRING: <<<db-connection-string>>>
      RABBITMQ_PASSWORD: <<<rabbitmq-password>>>
      azurestorageaccountkey: <<<azurestorageaccountkey>>>
      azurestorageaccountname: <<<azurestorageaccountname>>>
    kind: Secret
    metadata:
      creationTimestamp: null
      name: '{{name}}-secrets'
      namespace: '{{coral.workspace}}-{{coral.app}}'
      ```

2. The pipline creates indivial secrets for each of the secret tags such as (Kubernetes Certificate Secrets, Istio Gateway Certificate etc), and stores them in AKV secrets with names matching their corresponding secret tags from the secret.enc.yaml in the control plane. For example, if an secret file `mysecret.enc.yaml` is created in the control-plane, with the tag `DB_CONNECTION_STRING: <<<db-connection-string>>>` then a AKV secret with the name `db-connection-string` will be created in the configured AKV instance, with the base64 encoded secret value.

    - These secret values are only auto-generated for the existing / default secrets which ship with the control-plane and would need to be expanded to include any newly created secrets.
    - Users have the option to provide their own secret values by manually creating secrets in AKV using the steps [here](../../templates/istio-service/README.md#Create-Azure-Key-Vault-Secrets)

3. The CI / CD pipeline is triggered.
4. The Coral render in pipeline processes secret manifests and copies them to GitOps without the secrets.
5. Zarf scripts copy the post-rendered application secret manifests without secrets from gitops to controlplane/zarf directory
6. The pipline finds all unique secret tags and stores them as list.
7. For each secret tag, the pipeline replaces the contents of each secret yaml `.enc.yaml` file with the secret value obtained from AKV.
8. The pipeline will then encrypt all `.enc.yaml` files in gitops with SOPS.
9. The pipeline commits the SOPS encrypted files to gitops.
10. For Zarf, the pipeline encrypts all `.enc.yaml` files in Zarf directory with sealed secrets.
11. The pipeline then commits the sealed secrets encrypted files to control plane's Zarf directory.
12. Then at the end the pipline does a Flux bootstrap the cluster with GitOps.

Refer to the [flow chart diagram](workflow-flowchart-secrets.md) created using mermaid for specific details of the pipeline.

### File and AKV Secret Naming Conventions

As stated in the Overview / Workflow section, the following naming conventions apply and must be followed.

1. Each secret file created in the control-plane must have a `.enc.yaml` extension and be in the format `<secret name>.enc.yaml`, for example `mysecret.enc.yaml`.
2. Each secret file created in the control-plane must have a matching secret in AKV where the AKV secret name matches the secret tag from the secret yaml file.  For example, if the control-plane secret is `mysecret.enc.yaml`,and has the secret tag `DB_CONNECTION_STRING: <<<db-connection-string>>>` then a AKV secret would be `db-connection-string`.

### Base64 Encoding Secrets

> **Note**  This is handled by pipeline and no manual steps are required here

All raw secret values stored in AKV must first be base64 encoded.  Base64 encoded secrets should be a single string value, without newlines.  The following command can be used to base64 encode a file without newlines:

```bash
base64 <secret file> -w 0
```

For example, encoding the secret file `templates/istio-service/deploy/secrets.enc.yaml`:

```bash
base64 templates/istio-service/deploy/secrets.enc.yaml -w 0
```

This command generates a base64 encoded string which should then be entered as the AKV secret's value.

### Azure Key Vault Max Secret Length

Azure Key Vault limits the maximum length of an individual secret to 25KB.  Because of this, we recommend keeping the size of your secrets created using the process above as small as possible in order to stay within this size limit.  While most secrets themselves are not likely to exceed this limit often, wrapping them in a Kubernetes secret does extend the length.  Keeping the Kubernetes secret object slim, with minimal metadata, labels, etc. is the recommended way to minimize the size of your secrets and stay within the limit.

An alternative / enhancement which could help to stay within the size limit is to include only the secret itself within AKV and not the entire k8s object.  While this design does increase the likelihood secrets will fit within the size limit, it does add additional complexity as it requires inserting the secret data into an existing k8s secret yaml structure.  The workflow of this design would be:

1. The `*.enc.yaml` placeholder files would be modified to include the Kubernetes object without the secret data.
2. AKV secrets would be updated to only store secret data and not the entire k8s object.
3. The CI / CD pipeline would be updated to insert the secret data into the `*.enc.yaml` files instead of copying the entire k8s object including the secret into each file.

This feature may be implemented in future releases.

### Azure SQL Edge Secrets

The MS SQL db password secret is generated as part of the pipeline, base64 encoded and saved into the AKV instance. This is done in the AKV section of the `infrastructure/deploy.sh` file by invoking the `scripts/pipeline/generateSecrets.sh` file.

The random password is generated and the secret created with:

```bash
kubectl create secret generic azure-sql-edge-secrets -n infrastructure \
    --from-literal=sql-hostname=azure-sql-edge-service \
    --from-literal=sql-username=sa \
    --from-literal=sql-password=$sql_password \
    --dry-run=client -o yaml | base64 -w 0
```

This can be done manually with your own password independently if the test deployment automation is not used (by setting `DEPLOY_INFRA` pipeline variable to `false`).

The datasource ConfigMap is generated in a similar manner, however the `manifests/azure-sql-edge/datasource.yaml` file is used as the base and the secret injected before saving to AKV.

```yaml
# This file is provided to help as the platform understand what the encrypted version of this file looks like.  
# There are no actions for the Platform team with this file.  
# Do not populate the password. Instead review the documentation on how to inject secrets: docs/design-decisions/secret-management.md
# Do not remove this file as it serves as the template for encryption.

apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-azure-sql-edge
  namespace: infrastructure
  labels:
    grafana_datasource: "1"
data:
  datasources-azure-sql-edge.yaml: |
    apiVersion: 1
    datasources:
    - name: mssql
      type: mssql
      url: azure-sql-edge-service.infrastructure:1433
      database: master
      user: sa
      secureJsonData:
        password: <PIPELINE_REPLACES>
      isDefault: true
```

Both models are possible for your deployment scenario and these are used to illustrate accordingly.

## Secret Variables in CI / CD Pipelines

This control plane uses two secrets in the CI / CD pipeline, `GITOPS_PAT` and `AZURE_CREDENTIALS`.  `GITOPS_PAT` is used by Flux to update the cluster-gitops repository.  `AZURE_CREDENTIALS` is used to connect to Azure Key Vault to manage encryption / decryption keys, control-plane / application secrets and query Kubernetes cluster connection info and credentials used for deploying SOPS keys.

Although not recommended, it is possible users of this seed might wish to add additional secret variables to extend the pipeline.  To achieve this, the recommended approach is to use the source control platform's implementation to create, manage and reference secrets.  For GitHub, this would be [encrypted-secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets), and for GitLab [secrets](https://docs.gitlab.com/charts/installation/secrets.html).

## Manual Secret Management (Informational Only)

This section describes how to manually perform secret / file encryption and deploy the encrypted resulting files to the cluster.  These steps are provided for information purposes only and are included to provide context on how the encryption process works.  These steps are not required as secrets are automatically detected and encrypted by the CI / CD pipeline.

### Manually Collecting Encryption Keys from Azure Key Vault

Two public / private key pairs, one for SOPS and one for Sealed Secrets, are created as part of the CI / CD pipeline.  After creation, these keys are uploaded to AKV and stored in four total secrets:
A SOPS public / private key pair is created as part of the CI / CD pipeline and uploaded to Azure Key Vault.  Two AKV secrets are created to store this key pair:

- `SOPS_PUBLIC_KEY_SECRET_NAME`: Defines the name of the AKV secret which stores the SOPS public key.
- `SOPS_PRIVATE_KEY_SECRET_NAME`: Defines the name of the AKV secret which stores the SOPS private key.
- `SS_PUBLIC_KEY_SECRET_NAME`: Defines the name of the AKV secret which stores the SS public key.
- `SS_PRIVATE_KEY_SECRET_NAME`: Defines the name of the AKV secret which stores the SS private key.

### Manually Creating and Deploying Encrypted Secrets

First, install sops by running the script from [here](https://github.com/benc-uk/tools-install/blob/master/sops.sh).

For SOPS encryption operations, the value of the `--age` parameter should be the value of the `public key:` line from this secret.  In this example, the value will be `age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq`.

For example, encrypting a secret using with SOPS using this public key:

```bash
sops --encrypt --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' cacerts.yaml > cacerts.enc.yaml
```

After the SOPS keys have been created and deployed to the cluster, we're ready to start creating and encrypting secrets.  The first stop is to create a regular, unencrypted, Kubernetes secret.  For example:

```bash
cat <<EOF > secret.yaml
apiVersion: v1
data:
  username: user1
  password: abc123
kind: Secret
metadata:
  creationTimestamp: null
  name: test-secret
  namespace: my-app
EOF
```

Kubernetes secrets are only accessible within a single namespace.  The namespace specified when creating the secret should be the one containing the apps / resources which will use it.  For example, if you're creating a secret to be used by apps / resources in the `my-app` namespace, the secret should also specify that namespace.

SOPS provides a CLI to encrypt and decrypt files. We will use this CLI going forward to encrypt raw secret files. Install the CLI using instructions [here](https://github.com/mozilla/sops#download).

Next, we will encrypt secret.yaml using SOPS and the public key we created earlier.  Encryption is performed using AGE as indicated by the `--age` flag

```bash
sops --encrypt --verbose --age '<your age public key>' --encrypted-regex '^(data|stringData)$' secrets.yaml > secrets.enc.yaml
```

For example:

```bash
sops --encrypt --verbose --age 'age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq' --encrypted-regex '^(data|stringData)$' secrets.yaml > secrets.enc.yaml
```

The inclusion of the `--encrypted-regex '^(data|stringData)$'` parameter configures SOPS to encrypt only objects under `data` and / or `stringData`, leaving the rest of the object as plain text which can be templated by Coral.

This produces the encrypted file `secret.enc.yaml`:

```yaml
cat secret.enc.yaml
apiVersion: v1
data:
    username: ENC[AES256_GCM,data:eR04eWg=,iv:Yv1jC6LKA9Q4Oi7bPJChiI6s6sdkEhrYwmJH0P85FI4=,tag:DduqeCGvenFhGfa6OTh71w==,type:str]
    password: ENC[AES256_GCM,data:SfeQzbWO,iv:rcQqGLtfdEeYpbcLMog9EOjmWvHPnsbh5Brxdj0zoo0=,tag:TpuJubOX2jef0ErkIpiZKQ==,type:str]
kind: Secret
metadata:
    creationTimestamp: null
    name: test-secret
    namespace: my-app
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1qyytj3h4z0w39h8t5cfd6089607p04smnxw58jmkwa2m8jxcmpcqjqg9jq
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBzbFc3dCtqdnp5cldlZGQy
            SjVtUTBydmpZVys0bXdOeDEzbDJlOTZDZFJRCm5Dd0xMd3RVUkUrYlZxb0pWbUky
            Y1NHdlgwMndSV0xRODk4M1F2a2FlVFkKLS0tIEJTOGRoZjFLQUtZa0c0NlVZUzRQ
            VXJOdlM0anp4ZkwySUJIL1lHdk5CMk0KT7+rcVRC/5HtFMPTrbeJw07w1MQKAEDR
            o+d38DIxFg6sAvhvWcS0MYAxBqXKmaA9KwAgYwk5qWLqlbKdN6fi2g==
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2022-12-20T17:58:36Z"
    mac: ENC[AES256_GCM,data:4PR3TPWBJkp9t/52bSRoLj0mLheJxiDEu8WiTu6QIUgrMuQGWmNKwFlEE9oIc4OgjPhW6KtJhnnVUZfY4GxEr8DsLuuJLK6VJ5q9r2L3mU2bMJPu/7GhRya00NmzbQ+iquOP5LG3cRDcRrG0jRlMcXgEgn4LtztMgjLuLFJZKNI=,iv:7TkroDIrQqOjjjN0f568Qokd2k0ZIi+BUrZKOTnJ3bk=,tag:BGiSrVI2siVr/mjOHlxxJw==,type:str]
    pgp: []
    encrypted_regex: ^(data|stringData)$
    version: 3.7.3
```

This file can now be committed to the control-plane where it will be deployed to the cluster using Flux.  The control-plane provides the `manifests/secrets` directory to store encrypted secrets.  To deploy the `secret.enc.yaml` file from our example above, copy this file into the `manifests/secrets` directory, then add it to the kustomization.yaml file like so:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ghcr-credentials.enc.yaml
  - secret.enc.yaml
```

Next, commit your changes.  The secret will be deployed to the cluster and automatically decrypted.

> **Warning: Remember to delete the raw / unencrypted `secrets.yaml` file!**

## Deploying Applications

More info on deploying applications is available in the istio-service template's [README](./../../templates/istio-service/README.md).
