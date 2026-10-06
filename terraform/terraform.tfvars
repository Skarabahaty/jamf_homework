# Copy to terraform.tfvars locally, or set equivalent TF_VAR_* environment variables.
# This file intentionally contains placeholders, not live IDs or secrets.
github_organization = "jamf-test-org"

repositories = {}

app_installations = {
  linear_code = {
    installation_id = 166419116
    repositories    = []
  }
  today_i_learned = {
    installation_id = 166638533
    repositories    = []
  }
}

protected_branches = {}