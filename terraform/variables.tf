variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "devops-task"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "github_repo" {
  type        = string
  description = "amirhamza0110-eng/Devops-task allowed to assume the CI role via OIDC"
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Set false if the GitHub OIDC provider already exists in the account"
}
