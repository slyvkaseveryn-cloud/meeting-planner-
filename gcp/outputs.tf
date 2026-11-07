output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "api_service" {
  value = google_cloud_run_v2_service.api.name
}

output "image_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "db_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}
