#!/bin/bash

SERVICE=fluid-droplet-shipping-options
SERVICE_JOBS_MIGRATIONS=fluid-droplet-shipping-options-migrations
SERVICE_JOBS_WORKER_POOL=fluid-droplet-shipping-options-jobs
IMAGE_URL=europe-west1-docker.pkg.dev/fluid-417204/fluid-droplets/fluid-droplet-shipping-options-rails/web:latest

# Variables array - add your variables here
VARS=(
  "EXAMPLE_VARIABLE=example_value"
  "EXAMPLE_VARIABLE2=example_value2"
  "ANOTHER_VAR=another_value"
  # Add more variables as needed
)

# Build the environment variables arguments for Cloud Run
CLOUD_RUN_ENV_ARGS=""
for var in "${VARS[@]}"; do
  CLOUD_RUN_ENV_ARGS="$CLOUD_RUN_ENV_ARGS --update-env-vars $var"
done

# Update the environment variables for the service cloud run web Cloud Run migrations
gcloud run jobs update $SERVICE_JOBS_MIGRATIONS --region=us-south1 --project=fluid-prod-0 --image $IMAGE_URL $CLOUD_RUN_ENV_ARGS

# Update the environment variables for the service cloud run web
echo "Updating Cloud Run service: $SERVICE"
gcloud run services update $SERVICE --region=us-south1 --project=fluid-prod-0 --image $IMAGE_URL $CLOUD_RUN_ENV_ARGS

# Update the environment variables for the Solid Queue worker pool
echo "Updating Cloud Run worker pool: $SERVICE_JOBS_WORKER_POOL"
gcloud beta run worker-pools update $SERVICE_JOBS_WORKER_POOL --region=us-south1 --project=fluid-prod-0 --image $IMAGE_URL $CLOUD_RUN_ENV_ARGS
