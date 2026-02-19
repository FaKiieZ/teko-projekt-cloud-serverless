# 1. Provider & Project Setup
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 2. Enable Required APIs
resource "google_project_service" "services" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "firebase.googleapis.com",
    "alloydb.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com"
  ])
  service = each.key
  disable_on_destroy = false
}

# 3. Networking (VPC & Connector)
resource "google_compute_network" "vpc_network" {
  name = "ticketing-vpc"
  auto_create_subnetworks = true
  depends_on = [google_project_service.services]
}

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "default" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

resource "google_vpc_access_connector" "connector" {
  name          = "vpc-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc_network.name
}

# 4. Database: AlloyDB (PostgreSQL)
resource "google_alloydb_cluster" "default" {
  cluster_id = "ticketing-cluster"
  location   = var.region

  network_config {
    network = google_compute_network.vpc_network.id
  }

  initial_user {
    user     = "postgres"
    password = var.db_password
  }
  
  depends_on = [google_service_networking_connection.default]
}

resource "google_alloydb_instance" "default" {
  cluster       = google_alloydb_cluster.default.name
  instance_id   = "ticketing-instance"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = 2
  }
}

# 5. Messaging: Pub/Sub Topic (Queue)
resource "google_pubsub_topic" "ticket_queue" {
  name = "ticket-processing-queue"
}

# 6. Database: Firestore (Native Mode)
resource "google_firestore_database" "database" {
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  # Ensure API is enabled first
  depends_on = [google_project_service.services]
}

# 7. Storage: Bucket for Function Code
resource "google_storage_bucket" "code_bucket" {
  name     = "${var.project_id}-function-source"
  location = "US"
  uniform_bucket_level_access = true
}

# --- Zip and Upload Validation Function ---
data "archive_file" "valid_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/validation"
  output_path = "${path.module}/files/validation.zip"
}

resource "google_storage_bucket_object" "valid_code" {
  name   = "validation.${data.archive_file.valid_zip.output_md5}.zip"
  bucket = google_storage_bucket.code_bucket.name
  source = data.archive_file.valid_zip.output_path
}

# --- Zip and Upload Worker Function ---
data "archive_file" "worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/worker"
  output_path = "${path.module}/files/worker.zip"
}

resource "google_storage_bucket_object" "worker_code" {
  name   = "worker.${data.archive_file.worker_zip.output_md5}.zip"
  bucket = google_storage_bucket.code_bucket.name
  source = data.archive_file.worker_zip.output_path
}

# 8. Validation Function (HTTP Trigger, 2nd Gen)
resource "google_cloudfunctions2_function" "validation_fn" {
  name        = "validation-function"
  location    = var.region
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
    max_instance_count = 2
    available_memory   = "256Mi"
    timeout_seconds    = 60
    environment_variables = {
      TOPIC_ID   = google_pubsub_topic.ticket_queue.id
      API_SECRET = var.api_secret_validation
      ALLOYDB_IP = google_alloydb_instance.default.ip_address
    }
    vpc_connector = google_vpc_access_connector.connector.id
    vpc_connector_egress_settings = "ALL_TRAFFIC"
  }
}

# Allow unauthenticated access to the validation function (public API)
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloudfunctions2_function.validation_fn.location
  project  = google_cloudfunctions2_function.validation_fn.project
  service  = google_cloudfunctions2_function.validation_fn.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 9. Worker Function (Pub/Sub Trigger, 2nd Gen)
resource "google_cloudfunctions2_function" "worker_fn" {
  name        = "worker-function"
  location    = var.region
  description = "Processes tickets from Pub/Sub and writes to AlloyDB"

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
    max_instance_count = 2
    available_memory   = "256Mi"
    timeout_seconds    = 60
    environment_variables = {
      ALLOYDB_IP   = google_alloydb_instance.default.ip_address
      API_SECRET   = var.api_secret_worker
    }
    vpc_connector = google_vpc_access_connector.connector.id
    vpc_connector_egress_settings = "ALL_TRAFFIC"
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.ticket_queue.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}

# 10. Outputs
output "api_url" {
  value       = google_cloudfunctions2_function.validation_fn.url
  description = "The direct URL of the Validation Function (acting as API)"
}

output "alloydb_ip" {
  value       = google_alloydb_instance.default.ip_address
  description = "The private IP of the AlloyDB instance"
}