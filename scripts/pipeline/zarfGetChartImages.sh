#!/usr/bin/env bash

write_file() {
    local file=$1
    local content=$2
    local new=${3:-""}
    if [[ -n $new ]]; then echo -e "$content" >"$file"; else echo -e "$content" >>"$file"; fi
}

file="zarf/charts.txt"

get_chart_images() {
    if [[ "$#" -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Input must be in the format get_chart_images <name> <url>"
        exit 1
    fi
    local name=$1
    local url=$2
    local chart="$name-repo/$name"

    helm repo add "$name-repo" "$url" > /dev/null 2>&1
    helm repo update > /dev/null 2>&1

    write_file $file "\n$name"
    write_file $file "version: $(helm show chart "$chart" | yq '.version')"
    write_file $file "    images:"
    write_file $file "$(helm template temp "$chart" | yq '.. | select(has("image"))' | grep image: | sort --unique | sed 's/"//g' | sed 's/image:/      -/g')"
    # helm template temp "$chart" > "$name.yaml" # for finding missing images
}

write_file $file "Images listed in configurations only (must append):
istio-base
      - docker.io/istio/pilot:1.15.3
kube-prometheus-stack
      - quay.io/prometheus-operator/prometheus-config-reloader:v0.63.0
      
Chart versions and images:"
get_chart_images "elasticsearch"         "https://charts.bitnami.com/bitnami"
get_chart_images "fluent-bit"            "https://fluent.github.io/helm-charts"
get_chart_images "base"                  "https://istio-release.storage.googleapis.com/charts"
get_chart_images "gateway"               "https://istio-release.storage.googleapis.com/charts"
get_chart_images "istiod"                "https://istio-release.storage.googleapis.com/charts"
get_chart_images "kiali-operator"        "https://kiali.org/helm-charts"
get_chart_images "kibana"                "https://charts.bitnami.com/bitnami"
get_chart_images "kube-prometheus-stack" "https://prometheus-community.github.io/helm-charts"
get_chart_images "rabbitmq"              "https://charts.bitnami.com/bitnami"
get_chart_images "sealed-secrets"        "https://bitnami-labs.github.io/sealed-secrets"
get_chart_images "zipkin"                "https://ygqygq2.github.io/charts"
