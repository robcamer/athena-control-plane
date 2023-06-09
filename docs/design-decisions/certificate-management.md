# Certificate Management for the Network Observability Solution - Cloud Native

**Author:** Marshall Bentley
**Date:** 12/5/2022

## Context and Scope

This control-plane uses digitial certificates primarily to enable Istio security features.  Certificates are used to secure Istio service mesh communciations with HTTPS / TLS as well as to enable other identity and authentication features.  There are two main types of certificate mechanisms, inter-cluster and gateway.  Inter-cluster certificates are for workloads within the cluster are managed by the Istio Certificate Authority (CA).  A custom root certificate can be provisioned in this CA which is then used to sign all other certificates used within cluster workloads.  Gateway certificates are for securing ingress and egress gateway traffic and are created and deployed seperatly.

## Istio Inter-cluster Certificate Management

Many of Istio's security features rely on digital certificates.  An Istio installation includes its own certificate authority (CA) which runs within the Kubernetes cluster and is managed by Istio.  This CA performs certificate management tasks such as provisioning certificates and fulfilling certificate signing requests (CSR).  By default, the Istio CA generates self-signed root certificates during the first startup after initial deployment.  These root certs are then used to provision dedicated certs for each workload in the cluster which are used, among other things, to enable mTLS communication.

### Istio Custom Certificates

Istio provides several mechanisms to replace its self-signed root certificates with ones provided by an administrator.  Once replaced, these custom root certs are used to sign all other certs in the cluster.  This means that only the root certs need to be replaced to configure custom certs for the entire cluster.

Istio supports integrating with third-party / external CAs as well as using certificate management frameworks such as [cert-manager](https://istio.io/latest/docs/ops/integrations/certmanager/).  However, due to its simplicity and the requirement of this control-plane to function in disconnected scenarios, we utilize the `cacerts` mechanism.  Istio continually monitors the cluster for a secret named `cacerts`.  This name is special and is hardcoded into Istio.  If a secret with this name is present, Istio abandons its default behavior of creating self-signed certificates and instead uses the certificates stored in this secret.  If the secret is absent, it will continue with the self-signed cert flow.  In order to provision custom certificates, administrators / users of this control-plane should populate the `cacerts` secret with their custom root cert.

### Creating Kubernetes Certificate Secrets

As this control-plane leverages SOPS for secret management, the `cacerts` secret should be created and encrypted as a yaml file and stored in source control.  Flux continually synchronizes the source control repo and will automatically decrypt this secret and deploy it to the cluster.  The data contanted in a `cacerts` secret is as follows:

- ca-cert.pem: the generated intermediate certificates
- ca-key.pem: the generated intermediate key
- cert-chain.pem: the generated certificate chain which is used by istiod
- root-cert.pem: the root certificate

The following is an example of configuring this control-plane to use a custom certificate.

Optional: Create test certificates

```bash
# Create certs dir to store cert files
mkdir certs
cd certs

# Create test root certs
make -f ../scripts/Makefile.selfsigned.mk root-ca

# Create test intermediate certs
make -f ../scripts/Makefile.selfsigned.mk cluster1-cacerts

# Return to parent dir
cd ..
```

Create `cacerts` secret:

```bash
kubectl create secret generic cacerts -n infrastructure --dry-run=client \
    --from-file=ca-cert.pem \
    --from-file=ca-key.pem \
    --from-file=root-cert.pem \
    --from-file=cert-chain.pem \
    -o yaml | base64 -w 0 > cacerts.yaml
```

If you used the optional section to generate test certs, the command would be:

```bash
kubectl create secret generic cacerts -n infrastructure --dry-run=client \
    --from-file=certs/cluster1/ca-cert.pem \
    --from-file=certs/cluster1/ca-key.pem \
    --from-file=certs/cluster1/root-cert.pem \
    --from-file=certs/cluster1/cert-chain.pem \
    -o yaml | base64 -w 0 > cacerts.yaml
```

**Warning: If you created certs, make sure to delete them so they're not accidentally committed to source control!**

To deploy these secrets / certificates, follow the steps in the [secret management doc](./secret-management.md#automatic-secret-encryption-using-azure-key-vault-and-ci--cd-pipeline).

## Istio Gateway Certificate Management

Istio gateway certificates are used to secure ingress and egress traffic flowing through the cluster gateway.  This section describes how to create and deploy self-signed certificates and assign them to the cluster gateway.  Administrators wishing to use their own certificates my skip creating the self-signed certs and instead substitute their own.

### Creating Self-signed Gateway Certificates

First, create a directory to store the new certificates

```bash
mkdir gw_certs
```

Next, create a self-signed root certificate and key for the Network Observability control-plane.

```bash
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=Network Observability control-plane/CN=no-control-plane.com' -keyout gw_certs/no-control-plane.com.key -out gw_certs/no-control-plane.com.crt
```

Next, use the root cert to create a certificate and key for the gateway.  Since these are self-signed / test certificates, the gateway will have a different external IP address for each deployment.  Thus, a wildcard certificate is created.

```bash
openssl req -out gw_certs/wildcard.csr -newkey rsa:2048 -nodes -keyout gw_certs/wildcard.key -subj "/CN=*/O=Network Observability control-plane"
openssl x509 -req -sha256 -days 365 -CA gw_certs/no-control-plane.com.crt -CAkey gw_certs/no-control-plane.com.key -set_serial 0 -in gw_certs/wildcard.csr -out gw_certs/wildcard.crt
```

Next, create a Kubernetes TLS secret using the generated wildcard cert and store it in yaml file.

```bash
kubectl create -n infrastructure secret tls gateway-cert --dry-run=client \
  --key=gw_certs/wildcard.key \
  --cert=gw_certs/wildcard.crt \
  -o yaml | base64 -w 0 > gateway-cert.yaml
```

To deploy these secrets / certificates, follow the steps in the [secret management doc](./secret-management.md#automatic-secret-encryption-using-azure-key-vault-and-ci--cd-pipeline).
