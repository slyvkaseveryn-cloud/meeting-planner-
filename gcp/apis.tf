# APIs start switched off in a new project. Enabling them here keeps a fresh
# project reproducible from this folder alone.
locals {
  services = [
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  service = each.value
  # Turning an API off on destroy would break anything else in the project
  # that still uses it.
  disable_on_destroy = false
}
