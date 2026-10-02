locals {
  # A single key per desired (app, repository) grant makes access changes reviewable.
  app_repository_access = merge([
    for app, config in var.app_installations : {
      for repository in config.repositories :
      "${app}:${repository}" => {
        app             = app
        repository      = repository
        installation_id = config.installation_id
      }
    }
  ]...)
}

# These are existing repositories. Import them before applying:
# terraform import 'github_repository.managed["platform-infrastructure"]' platform-infrastructure
resource "github_repository" "managed" {
  for_each = var.repositories

  name                   = each.key
  description            = each.value.description
  visibility             = each.value.visibility
  has_issues             = each.value.has_issues
  has_projects           = each.value.has_projects
  has_wiki               = each.value.has_wiki
  allow_squash_merge     = each.value.allow_squash_merge
  allow_merge_commit     = each.value.allow_merge_commit
  allow_rebase_merge     = each.value.allow_rebase_merge
  delete_branch_on_merge = each.value.delete_branch_on_merge

  lifecycle {
    prevent_destroy = true
  }
}

# The allow-list is authoritative: removing a repository from an app's set
# produces a destroy in the plan and revokes that installation's access.
resource "github_app_installation_repository" "access" {
  for_each = local.app_repository_access

  installation_id = each.value.installation_id
  repository      = github_repository.managed[each.value.repository].name
}

resource "github_branch_protection" "main" {
  for_each = var.protected_branches

  repository_id = github_repository.managed[each.key].node_id
  pattern       = each.value.pattern

  enforce_admins = each.value.enforce_admins

  required_pull_request_reviews {
    required_approving_review_count = each.value.required_approving_reviews
    require_code_owner_reviews      = each.value.require_code_owner_reviews
    dismiss_stale_reviews           = each.value.dismiss_stale_reviews
  }

  dynamic "required_status_checks" {
    for_each = each.value.require_status_checks ? [1] : []
    content {
      strict   = true
      contexts = tolist(each.value.required_status_checks)
    }
  }
}
