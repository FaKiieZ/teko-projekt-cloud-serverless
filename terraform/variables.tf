variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Default Region"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "Database Password (AlloyDB)"
  type        = string
  sensitive   = true
}

variable "api_secret_validation" {
  description = "Secret key for the validation function"
  type        = string
  sensitive   = true
}

variable "api_secret_worker" {
  description = "Secret key for the worker function"
  type        = string
  sensitive   = true
}
