# The backend image (0.5 GB free). make gcp-push builds and pushes it.
resource "google_artifact_registry_repository" "backend" {
  repository_id = var.project_name
  format        = "DOCKER"
  location      = var.region
  description   = "Spry backend images"

  # Keep the three newest images, so storage stays inside the free 0.5 GB.
  cleanup_policies {
    id     = "keep-latest-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.this]
}
