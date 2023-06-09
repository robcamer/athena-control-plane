#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script used get generate infrastructure certificates and secrets
########

# shellcheck disable=SC1091
source "$(dirname "$0")"/common.sh

# Creating Kubernetes Certificate Secrets
# Ref: docs/design-decisions/certificate-management.md#creating-kubernetes-certificate-secrets

if [[ $(does_akv_secret_exist istio-ca-cert) == "false" ]] && [[ $(does_akv_secret_exist istio-ca-key) == "false" ]] && [[ $(does_akv_secret_exist istio-cert-chain) == "false" ]] && [[ $(does_akv_secret_exist istio-root-cert) == "false" ]]; then
    echo "Generating Istio cluster certificate"
    if [[ ! -f ./certs/cluster1/ca-cert.pem ]] || [[ ! -f ./certs/cluster1/ca-key.pem ]] || [[ ! -f ./certs/cluster1/root-cert.pem ]]; then
        mkdir certs
        cd certs

        # Create test root certs
        make -f ../scripts/Makefile.selfsigned.mk root-ca

        # Create test intermediate certs
        make -f ../scripts/Makefile.selfsigned.mk cluster1-cacerts

        # Return to parent dir
        cd ..
    fi

    set_akv_secret istio-ca-cert "$(base64 -w 0 < certs/cluster1/ca-cert.pem)"
    set_akv_secret istio-ca-key "$(base64 -w 0 < certs/cluster1/ca-key.pem)"
    set_akv_secret istio-cert-chain "$(base64 -w 0 < certs/cluster1/cert-chain.pem)"
    set_akv_secret istio-root-cert "$(base64 -w 0 < certs/cluster1/root-cert.pem)"
else
    echo "Istio Cluster cert exists in AKV"
fi

# Istio Gateway Certificate Management
# Ref: docs/design-decisions/certificate-management.md#istio-gateway-certificate-management

if [[ $(does_akv_secret_exist istio-gateway-cert) == "false" ]] && [[ $(does_akv_secret_exist istio-gateway-key) == "false" ]]; then
    echo "Generating Istio gateway certificate"
    if [[ ! -f ./gw_certs/wildcard.key ]] || [[ ! -f ./gw_certs/wildcard.crt ]]; then
        mkdir gw_certs

        # Create a self-signed root certificate and key
        openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=Network Observability control-plane/CN=no-control-plane.com' -keyout gw_certs/no-control-plane.com.key -out gw_certs/no-control-plane.com.crt

        # Create a certificate and key for the gateway
        openssl req -out gw_certs/wildcard.csr -newkey rsa:2048 -nodes -keyout gw_certs/wildcard.key -subj "/CN=*/O=Network Observability control-plane"
        openssl x509 -req -sha256 -days 365 -CA gw_certs/no-control-plane.com.crt -CAkey gw_certs/no-control-plane.com.key -set_serial 0 -in gw_certs/wildcard.csr -out gw_certs/wildcard.crt
    fi

    set_akv_secret istio-gateway-cert "$(base64 -w 0 < gw_certs/wildcard.crt)"
    set_akv_secret istio-gateway-key "$(base64 -w 0 < gw_certs/wildcard.key)"
else
    echo "Istio Gateway cert exists in AKV"
fi

# Create random passowrd for SQL installation if present
if [[ -d manifests/azure-sql-edge ]]; then
    if [[ $(does_akv_secret_exist azure-sql-edge-password) == "false" ]]; then
        echo "Generating SQL password secret"
        set_akv_secret azure-sql-edge-password "$(base64_encode_one_line "$(generate_password)")"
    else
        echo "SQL password secret exists in AKV"
    fi
fi

# Create random passowrd assets for RabbitMQ installation if present
if [[ -d manifests/rabbitmq ]]; then
    if [[ $(does_akv_secret_exist rabbitmq-erlang-cookie) == "false" ]]; then
        echo "Generating RabbitMQ erlang secret"
        set_akv_secret rabbitmq-erlang-cookie "$(base64_encode_one_line "$(generate_password 36)")"
    else
        echo "RabbitMQ erlang-cookie secret exists in AKV"
    fi

    if [[ $(does_akv_secret_exist rabbitmq-password) == "false" ]]; then
        echo "Generating RabbitMQ password secret"
        set_akv_secret rabbitmq-password "$(base64_encode_one_line "$(generate_password)")"
    else
        echo "RabbitMQ password secret exists in AKV"
    fi
fi
