variable "github_organization" {
  description = "GitHub organization that owns the governed repositories."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_organization))
    error_message = "github_organization must be a valid GitHub organization name."
  }
}

variable "github_token" {
  description = "User-authenticated GitHub token for repository administration and app-installation management. Do not use the Actions GITHUB_TOKEN or an installation token."
  type        = string
  sensitive   = true
  default     = null
}

variable "repositories" {
  description = "Existing repositories to govern. Import each resource before the first apply."
  type = map(object({
    description            = string
    visibility             = optional(string, "private")
    has_issues             = optional(bool, true)
    has_projects           = optional(bool, false)
    has_wiki               = optional(bool, false)
    allow_squash_merge     = optional(bool, true)
    allow_merge_commit     = optional(bool, false)
    allow_rebase_merge     = optional(bool, false)
    delete_branch_on_merge = optional(bool, true)
  }))
}

variable "app_installations" {
  description = "GitHub App installation IDs and the exact repositories each app may access."
  type = map(object({
    installation_id = number
    repositories    = set(string)
  }))

  validation {
    condition     = alltrue([for app, config in var.app_installations : config.installation_id > 0])
    error_message = "Every GitHub App installation_id must be a positive, real installation ID supplied by the operator."
  }

  validation {
    condition = alltrue(flatten([
      for app, config in var.app_installations : [
        for repository in config.repositories : contains(keys(var.repositories), repository)
      ]
    ]))
    error_message = "App access may reference only repositories declared in var.repositories."
  }
}

variable "protected_branches" {
  description = "Branch protection policy by repository. Empty set disables management for a repository."
  type = map(object({
    pattern                    = optional(string, "main")
    enforce_admins             = optional(bool, true)
    require_code_owner_reviews = optional(bool, true)
    required_approving_reviews = optional(number, 1)
    dismiss_stale_reviews      = optional(bool, true)
    require_status_checks      = optional(bool, true)
    required_status_checks     = optional(set(string), ["terraform"])
  }))
  default = {}
}
