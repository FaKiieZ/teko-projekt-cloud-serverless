# 1. Provider Setup
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    cockroach = {
      source  = "cockroachdb/cockroach"
      version = "1.17.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "1.25.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region_gcloud
}

provider "cockroach" {
  apikey = var.cockroach_api_key
}

# PostgreSQL Provider für die Schema-Provisionierung
provider "postgresql" {
  host            = cockroach_cluster.ticketing_db.regions[0].sql_dns
  port            = 26257
  database        = cockroach_database.main.name
  username        = cockroach_sql_user.db_user.name
  password        = var.db_password
  sslmode         = "require"
  connect_timeout = 15
}

# 2. Erforderliche APIs aktivieren
resource "google_project_service" "services" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# 3. CockroachDB Serverless
resource "cockroach_cluster" "ticketing_db" {
  name           = "ticketing-cluster"
  cloud_provider = "GCP"
  plan           = "BASIC"
  regions = [
    {
      name = var.region_cockroach
    }
  ]
  serverless = {
    usage_limits = {
      request_unit_limit = 1000000
      storage_mib_limit  = 5120
    }
  }
}

# Datenbank-Nutzer erstellen
resource "cockroach_sql_user" "db_user" {
  name       = "ticket_admin"
  password   = var.db_password
  cluster_id = cockroach_cluster.ticketing_db.id
}

# Datenbank innerhalb des Clusters erstellen
resource "cockroach_database" "main" {
  name       = "ticketing"
  cluster_id = cockroach_cluster.ticketing_db.id

  depends_on = [cockroach_sql_user.db_user]
}

# DB Schema Provisioning

# Wir nutzen ein lokales Node.js Script, um das Schema zu initialisieren.
# Dies stellt sicher, dass die Tabellen und das initiale Event vorhanden sind.
resource "null_resource" "db_init" {
  depends_on = [cockroach_database.main, cockroach_sql_user.db_user]

  provisioner "local-exec" {
    # Installiert Abhängigkeiten (pg) und führt das Script `init-db.js` aus
    command = "npm install && node init-db.js"
    environment = {
      DB_HOST     = cockroach_cluster.ticketing_db.regions[0].sql_dns
      DB_NAME     = cockroach_database.main.name
      DB_USER     = cockroach_sql_user.db_user.name
      DB_PASSWORD = var.db_password
    }
  }

  triggers = {
    # Führt das Script erneut aus, wenn sich der Host ändert
    db_host = cockroach_cluster.ticketing_db.regions[0].sql_dns
  }
}

# 4. Messaging: Pub/Sub Topic
resource "google_pubsub_topic" "ticket_queue" {
  name = "ticket-processing-queue"
}

# 5. Storage: Bucket für Function Code
resource "google_storage_bucket" "code_bucket" {
  name     = "${var.project_id}-function-source"
  location = "US"
  uniform_bucket_level_access = true
}

# Functions zippen und hochladen
data "archive_file" "valid_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/validation"
  output_path = "${path.module}/files/validation.zip"
}

data "archive_file" "worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/worker"
  output_path = "${path.module}/files/worker.zip"
}

resource "google_storage_bucket_object" "valid_code" {
  name   = "validation.${data.archive_file.valid_zip.output_md5}.zip"
  bucket = google_storage_bucket.code_bucket.name
  source = data.archive_file.valid_zip.output_path
}

resource "google_storage_bucket_object" "worker_code" {
  name   = "worker.${data.archive_file.worker_zip.output_md5}.zip"
  bucket = google_storage_bucket.code_bucket.name
  source = data.archive_file.worker_zip.output_path
}

# 6. Validation Function (HTTP)
resource "google_cloudfunctions2_function" "validation_fn" {
  name        = "validation-function"
  location    = var.region_gcloud
  description = "Validates ticket requests and queues them"

  build_config {
    runtime     = "nodejs24"
    entry_point = "validateTicket"
    source {
      storage_source {
        bucket = google_storage_bucket.code_bucket.name
        object = google_storage_bucket_object.valid_code.name
      }
    }
  }

  service_config {
    max_instance_count = 30
    available_memory   = "256Mi"

    environment_variables = {
      TOPIC_ID    = google_pubsub_topic.ticket_queue.id
      DB_HOST     = cockroach_cluster.ticketing_db.regions[0].sql_dns
      DB_NAME     = cockroach_database.main.name
      DB_USER     = cockroach_sql_user.db_user.name
      DB_PASSWORD = var.db_password
    }
  }
}

# Zugriffskontrolle für Users
resource "google_cloud_run_service_iam_member" "validation_invoker" {
  for_each = toset(var.authorized_invokers)

  service  = google_cloudfunctions2_function.validation_fn.name
  location = google_cloudfunctions2_function.validation_fn.location
  role     = "roles/run.invoker"
  member   = each.value

  depends_on = [
    google_project_service.services,
    google_cloudfunctions2_function.validation_fn
  ]
}

# 7. Worker Function (Pub/Sub Trigger)
resource "google_cloudfunctions2_function" "worker_fn" {
  name        = "worker-function"
  location    = var.region_gcloud
  description = "Processes tickets from Pub/Sub and writes to CockroachDB"

  build_config {
    runtime     = "nodejs24"
    entry_point = "processTicket"
    source {
      storage_source {
        bucket = google_storage_bucket.code_bucket.name
        object = google_storage_bucket_object.worker_code.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    available_memory   = "256Mi"

    environment_variables = {
      DB_HOST     = cockroach_cluster.ticketing_db.regions[0].sql_dns
      DB_NAME     = cockroach_database.main.name
      DB_USER     = cockroach_sql_user.db_user.name
      DB_PASSWORD = var.db_password
    }
  }

  event_trigger {
    trigger_region = var.region_gcloud
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.ticket_queue.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}

# 8. Outputs
output "db_host" {
  value = cockroach_cluster.ticketing_db.regions[0].sql_dns
}

output "api_url" {
  value = google_cloudfunctions2_function.validation_fn.url
}