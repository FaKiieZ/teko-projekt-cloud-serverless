variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region_gcloud" {
  description = "Default Region for Google Cloud"
  type        = string
  default     = "us-central1"
}

variable "region_cockroach" {
  description = "Default Region for CockroachDB"
  type        = string
  default     = "europe-west3"
}

variable "db_password" {
  description = "Database Password (Cockroach)"
  type        = string
  sensitive   = true
}

variable "cockroach_api_key" {
  description = "API Key for Cockroach DB"
  type        = string
  sensitive   = true
}

variable "invoker_emails" {
  description = "Email addresses of users allowed to invoke the validation function"
  type        = list(string)
}