# Copy to terraform.tfvars locally, or set equivalent TF_VAR_* environment variables.
# This file intentionally contains placeholders, not live IDs or secrets.
github_organization = "jamf-test-org"

repositories = {
  platform-infrastructure = {
    description = "Platform infrastructure managed through GitOps"
    visibility  = "public"
  }
  service-catalog = {
    description = "Service catalog managed through GitOps"
    visibility  = "public"
  }
  never-gonna-give-you-up = {
    description = "Rolling catalog managed through GitOps"
    visibility  = "public"
  }
}

app_installations = {
  linear_code = {
    installation_id = 166419116
    repositories    = ["service-catalog"]
  }
  today_i_learned = {
    installation_id = 166638533
    repositories    = ["platform-infrastructure"]
  }
}

protected_branches = {
  platform-infrastructure = {
    pattern                    = "main"
    required_approving_reviews = 1
    required_status_checks     = ["terraform"]
  }
  service-catalog = {
    pattern                    = "main"
    required_approving_reviews = 1
    required_status_checks     = ["terraform"]
  }
  never-gonna-give-you-up = {
    pattern                    = "main"
    required_approving_reviews = 1
    required_status_checks     = ["terraform"]
  }
}

