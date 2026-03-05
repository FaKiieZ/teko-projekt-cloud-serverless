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

variable "authorized_invokers" {
  description = "List of IAM members authorized to invoke the validation function (e.g., 'user:email@domain.com', 'group:team@domain.com')."
  type        = list(string)
  default     = []
}
