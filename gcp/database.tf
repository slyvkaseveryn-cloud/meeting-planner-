# Cloud SQL for PostgreSQL, the smallest tier. It bills every hour it runs,
# idle or not: set db_running = false to stop it, terraform destroy to end it.
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-pg"
  database_version = "POSTGRES_16"
  region           = var.region

  # A lab database: terraform destroy must be able to remove it.
  deletion_protection = false

  settings {
    # Shared-core tiers exist only in the Enterprise edition.
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    availability_type = "ZONAL"
    activation_policy = var.db_running ? "ALWAYS" : "NEVER"

    disk_type       = "PD_SSD"
    disk_size       = 10
    disk_autoresize = false

    # No backups or point-in-time recovery: they bill storage, and the data
    # is demo data that the migrations and the seed recreate.
    backup_configuration {
      enabled = false
    }

    # A public IP with no authorised networks: nothing can reach it directly.
    # Cloud Run connects through the Cloud SQL connector, authorised by IAM.
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    user_labels = {
      project    = var.project_name
      managed-by = "terraform"
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "meetings" {
  name     = "meetings"
  instance = google_sql_database_instance.main.name
}

# Letters and digits only: the URL goes through alembic's config parser,
# where % is special.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "app"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# The whole DATABASE_URL is the secret: the API reads it from Secret Manager,
# never from a file or a plain environment variable in the console.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql+asyncpg://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.app.name,
    random_password.db.result,
    google_sql_database.meetings.name,
    google_sql_database_instance.main.connection_name,
  )
}
