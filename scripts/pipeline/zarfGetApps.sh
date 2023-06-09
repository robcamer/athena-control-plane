#!/usr/bin/env bash

set -euo pipefail

########
# Description:
# * Script to copy app folders from the GitOps repo into the Zarf folder
# * These need to be imported before secrets are encrypted
########

# Flatten and copy GitOps rendered app yaml with secrets to zarf
find gitops -type f -name zarf.yaml | while read -r item; do
    folder="${item/$(basename "${item}")/""}"
    tmp="$(echo "$folder" | awk -F "/" '{print $3,$5,$6}')"
    destination="controlplane/zarf/${tmp// /-}"
    echo "Copying rendered apps with secrets: $destination"
    rm -rf "$destination" && mkdir -p "$destination" && cp -r "$folder"* "$destination"
done

# Copy GitOps rendered infra manifest secrets to zarf
mapfile -t gitops_secret_files < <(find gitops/applications/coral-system -iname '*.enc.yaml' | sort --unique)
for gitops_secret_file in "${gitops_secret_files[@]}"; do
    gitops_file_name=$(basename "$gitops_secret_file")
    echo "Copying rendered manifest secrets $gitops_file_name"
    find controlplane/zarf -iname "$gitops_file_name" -exec cp "$gitops_secret_file" {} \;
done
