#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_PATH="${1:-$SCRIPT_DIR/openapi-codegen.json}"

if ! command -v openapi-generator-cli >/dev/null 2>&1; then
  echo "error: openapi-generator-cli is not installed or not in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to read $CONFIG_PATH" >&2
  exit 1
fi

CONFIG_ABS="$CONFIG_PATH"
if [[ "$CONFIG_ABS" != /* ]]; then
  CONFIG_ABS="$REPO_ROOT/$CONFIG_ABS"
fi

template_dir="$(jq -r '.templateDir' "$CONFIG_ABS")"
generator_name="$(jq -r '.generatorName // "swift5"' "$CONFIG_ABS")"
project_name="$(jq -r '.projectName // "OpenAPIClient"' "$CONFIG_ABS")"
type_mappings="$(jq -r '(.typeMappings // {}) | to_entries | map("\(.key)=\(.value)") | join(",")' "$CONFIG_ABS")"
additional_properties="$(jq -r --arg projectName "$project_name" '(.additionalProperties // {}) + {projectName: $projectName} | to_entries | map("\(.key)=\(.value)") | join(",")' "$CONFIG_ABS")"

template_abs="$template_dir"
if [[ "$template_abs" != /* ]]; then
  template_abs="$REPO_ROOT/$template_abs"
fi

module_count="$(jq '.modules | length' "$CONFIG_ABS")"
for ((module_index = 0; module_index < module_count; module_index++)); do
  module_name="$(jq -r ".modules[$module_index].name" "$CONFIG_ABS")"
  input_dir="$(jq -r ".modules[$module_index].inputDir" "$CONFIG_ABS")"
  output_dir="$(jq -r ".modules[$module_index].outputDir" "$CONFIG_ABS")"
  tag_strategy="$(jq -r ".modules[$module_index].tagStrategy // \"fileName\"" "$CONFIG_ABS")"

  input_abs="$input_dir"
  output_abs="$output_dir"
  if [[ "$input_abs" != /* ]]; then
    input_abs="$REPO_ROOT/$input_abs"
  fi
  if [[ "$output_abs" != /* ]]; then
    output_abs="$REPO_ROOT/$output_abs"
  fi

  echo "Generating OpenAPI module: $module_name"
  mkdir -p "$output_abs/Apis" "$output_abs/Models"
  rm -rf "$output_abs/Apis" "$output_abs/Models"
  mkdir -p "$output_abs/Apis" "$output_abs/Models"

  json_files=()
  while IFS= read -r json_file; do
    json_files+=("$json_file")
  done < <(find "$input_abs" -maxdepth 1 -type f -name "*.json" | sort)
  if [[ "${#json_files[@]}" -eq 0 ]]; then
    echo "warning: no OpenAPI JSON files found in $input_abs" >&2
    continue
  fi

  for json_file in "${json_files[@]}"; do
    base_name="$(basename "$json_file")"
    api_name="$(python3 - "$json_file" <<'PY'
import os, re, sys
name = re.sub(r"\.json$", "", os.path.basename(sys.argv[1]), flags=re.IGNORECASE)
print("".join(part[:1].upper() + part[1:] for part in re.split(r"[-_]+", name) if part))
PY
)"
    normalized_file="$(mktemp "${TMPDIR:-/tmp}/openapi-${module_name}-XXXXXX.json")"
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openapi-gen-${module_name}-XXXXXX")"

    echo "  - $base_name -> ${api_name}API"
    python3 "$SCRIPT_DIR/preprocess-openapi.py" \
      --input "$json_file" \
      --output "$normalized_file" \
      --api-name "$api_name" \
      --tag-strategy "$tag_strategy"

    generator_args=(
      generate
      -i "$normalized_file"
      -g "$generator_name"
      -o "$temp_dir"
      -t "$template_abs"
      --global-property apis,models
    )

    if [[ -n "$type_mappings" ]]; then
      generator_args+=(--type-mappings "$type_mappings")
    fi

    if [[ -n "$additional_properties" ]]; then
      generator_args+=(--additional-properties "$additional_properties")
    fi

    openapi-generator-cli "${generator_args[@]}"

    generated_root="$temp_dir/OpenAPIClient/Classes/OpenAPIs"
    if [[ ! -d "$generated_root" ]]; then
      echo "error: generated OpenAPI root not found: $generated_root" >&2
      exit 1
    fi

    if [[ -d "$generated_root/Apis" ]]; then
      cp -R "$generated_root/Apis/." "$output_abs/Apis/"
    fi
    if [[ -d "$generated_root/Models" ]]; then
      cp -R "$generated_root/Models/." "$output_abs/Models/"
    fi

    rm -rf "$temp_dir"
    rm -f "$normalized_file"
  done
done
