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
}

app_installations = {
  security-scanner = {
    installation_id = 166419116 # Replace with the real installation ID.
    repositories    = ["service-catalog"]
  }
}

protected_branches = {
  platform-infrastructure = {
    pattern                    = "main"
    required_approving_reviews = 2
    required_status_checks     = ["terraform"]
  }
  service-catalog = {
    pattern                    = "main"
    required_approving_reviews = 1
    required_status_checks     = ["terraform"]
  }
}
