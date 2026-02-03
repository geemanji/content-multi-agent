#!/usr/bin/env bash
set -euo pipefail

service_name="${1:-}"
service_url="${2:-}"

if [[ -z "${service_name}" || -z "${service_url}" ]]; then
  echo "Usage: $0 <service-name> <service-url>" >&2
  exit 1
fi

agent_card_url="${service_url%/}/a2a/agent/.well-known/agent.json"

echo "Smoke check: ${service_name} -> ${agent_card_url}"

id_token="$(gcloud auth print-identity-token --audiences="${service_url}")"

curl -fSs \
  -H "Authorization: Bearer ${id_token}" \
  -H "Accept: application/json" \
  "${agent_card_url}" > /dev/null

echo "OK: ${service_name}"
