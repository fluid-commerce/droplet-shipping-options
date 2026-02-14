project_id = "fluid-417204"
region     = "us-west3"
zone       = "us-west3-b"

# variable module compute_instance and static_ip
vm_name      = "fluid-droplet-NAME-jobs-console"
machine_type = "e2-small"
# labels for the instance
environment            = "production"
purpose_compute_engine = "jobs"
project                = "fluid-droplet-NAME"

# service account email to compute engine
email_service_account = "106074092699-compute@developer.gserviceaccount.com"

# variable module container
#master key
container_rails_master_key        = ""
container_image                   = "us-west3-docker.pkg.dev/fluid-417204/fluid-droplets/fluid-droplet-NAME-rails/web:latest"
container_db_url_production       = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production?host="
container_db_url_production_queue = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_queue?host="
container_db_url_production_cache = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_cache?host="
container_db_url_production_cable = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_cable?host="

# variable module cloud_run fluid droplet exigo ordercalc rails
vpc_connector_cloud_run = "projects/fluid-417204/locations/us-west3/connectors/fluid-vpc-connector"
cloud_sql_instances_cloud_run = [
  "fluid-417204:us-west3:fluid-droplet-NAME"
]
environment_variables_cloud_run = {
  "CABLE_DATABASE_URL"  = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_cable?host=/cloudsql/fluid-417204:us-west3:fluid-droplet-NAME",
  "CACHE_DATABASE_URL"  = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_cache?host=/cloudsql/fluid-417204:us-west3:fluid-droplet-NAME",
  "DATABASE_URL"        = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production?host=/cloudsql/fluid-417204:us-west3:fluid-droplet-NAME",
  "QUEUE_DATABASE_URL"  = "postgresql://postgres:PASSWORD@localhost/fluid_droplet_NAME_production_queue?host=/cloudsql/fluid-417204:us-west3:fluid-droplet-NAME",
  "RACK_ENV"            = "production",
  "RAILS_ENV"           = "production",
  "RAILS_LOG_TO_STDOUT" = "enabled",
  "RAILS_MASTER_KEY"    = "",
  "SENTRY_DSN"          = "https://bf840ff3a60ff103deac474b04208bb1@o553113.ingest.us.sentry.io/4510885897830400"
}
