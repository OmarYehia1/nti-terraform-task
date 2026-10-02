terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  token = var.github_token
}

# --- Resources ---

resource "github_repository" "infra_repo" {
  name        = "devsecops-infrastructure"
  description = "Hybrid DevSecOps Infrastructure Managed by Terragrunt"
  visibility  = "private"
  auto_init   = true
}

resource "github_actions_secret" "aws_access_key" {
  repository      = github_repository.infra_repo.name
  secret_name     = "AWS_ACCESS_KEY_ID"
  plaintext_value = var.aws_access_key_id
}

resource "github_actions_secret" "aws_secret_key" {
  repository      = github_repository.infra_repo.name
  secret_name     = "AWS_SECRET_ACCESS_KEY"
  plaintext_value = var.aws_secret_access_key
}

# --- Variables ---

variable "github_token" {
  type      = string
  sensitive = true
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}