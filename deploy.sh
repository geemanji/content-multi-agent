#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

if [ -f ".env" ]; then
  source .env
fi

if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project -q)
fi
if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  echo "ERROR: Run 'gcloud config set project' command to set active project, or set GOOGLE_CLOUD_PROJECT environment variable."
  exit 1
fi

REGION="${GOOGLE_CLOUD_LOCATION}"
if [[ "${REGION}" == "global" ]]; then
  echo "GOOGLE_CLOUD_LOCATION is set to 'global'. Getting a default location for Cloud Run."
  REGION=""
fi

if [[ "${REGION}" == "" ]]; then
  REGION=$(gcloud config get-value compute/region -q)
  if [[ "${REGION}" == "" ]]; then
    REGION="us-central1"
    echo "WARNING: Cannot get a configured compute region. Defaulting to ${REGION}."
  fi
fi
echo "Using project ${GOOGLE_CLOUD_PROJECT}."
echo "Using compute region ${REGION}."

# Resolve symlinks by copying shared files
echo "Copying shared files to service directories..."

rm agents/researcher/adk_app.py agents/researcher/a2a_utils.py 2>/dev/null || true
cp shared/adk_app.py agents/researcher/
cp shared/a2a_utils.py agents/researcher/

rm agents/judge/adk_app.py agents/judge/a2a_utils.py 2>/dev/null || true
cp shared/adk_app.py agents/judge/
cp shared/a2a_utils.py agents/judge/

rm agents/content_builder/adk_app.py agents/content_builder/a2a_utils.py 2>/dev/null || true
cp shared/adk_app.py agents/content_builder/
cp shared/a2a_utils.py agents/content_builder/

rm agents/orchestrator/adk_app.py agents/orchestrator/a2a_utils.py agents/orchestrator/authenticated_httpx.py 2>/dev/null || true
cp shared/adk_app.py agents/orchestrator/
cp shared/a2a_utils.py agents/orchestrator/
cp shared/authenticated_httpx.py agents/orchestrator/

rm app/authenticated_httpx.py 2>/dev/null || true
cp shared/authenticated_httpx.py app/

gcloud run deploy researcher \
  --source agents/researcher \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
RESEARCHER_URL=$(gcloud run services describe researcher --region $REGION --project $GOOGLE_CLOUD_PROJECT --format='value(status.url)')

gcloud run deploy content-builder \
  --source agents/content_builder \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
CONTENT_BUILDER_URL=$(gcloud run services describe content-builder --region $REGION --project $GOOGLE_CLOUD_PROJECT --format='value(status.url)')

gcloud run deploy judge \
  --source agents/judge \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
JUDGE_URL=$(gcloud run services describe judge --region $REGION --project $GOOGLE_CLOUD_PROJECT --format='value(status.url)')

gcloud run deploy orchestrator \
  --source agents/orchestrator \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --no-allow-unauthenticated \
  --set-env-vars RESEARCHER_AGENT_CARD_URL=$RESEARCHER_URL/a2a/agent/.well-known/agent.json \
  --set-env-vars JUDGE_AGENT_CARD_URL=$JUDGE_URL/a2a/agent/.well-known/agent.json \
  --set-env-vars CONTENT_BUILDER_AGENT_CARD_URL=$CONTENT_BUILDER_URL/a2a/agent/.well-known/agent.json \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
ORCHESTRATOR_URL=$(gcloud run services describe orchestrator --region $REGION --project $GOOGLE_CLOUD_PROJECT --format='value(status.url)')

gcloud run deploy course-creator \
  --source app \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars AGENT_SERVER_URL=$ORCHESTRATOR_URL \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}"
