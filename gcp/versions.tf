terraform {
  required_version = ">= 1.10"

  # Its own workspace and state: a plan here cannot touch the AWS side (infra/).
  cloud {
    organization = "ooad-slyvkaseveryn"

    workspaces {
      name = "spry-severyn-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
}
