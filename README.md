# GitHub App access governance with Terraform

This example keeps GitHub App repository access and repository policy in code. `terraform/main.tf` manages existing repository settings, the desired app-to-repository grants, and branch protection. The GitHub provider is configured in `terraform/versions.tf`; the workflow plans on pull requests and applies to `main` after merge.

## Run the example

Use a test organization, two existing repositories, and two GitHub Apps installed in that organization with **selected repository** access. The example demonstrates two Apps across two repositories. Its values are placeholders: replace repository names, organization, and each installation ID with real values. Do not commit real tokens or private backend configuration.

1. Copy and edit the examples:

   ```sh
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   cp terraform/backend.hcl.example terraform/backend.hcl
   ```

   Set a user-authenticated `TF_VAR_github_token` in your shell or approved secret manager. It needs repository administration access for settings/branch protection and access to the App installations. The provider's `github_app_installation_repository` resource uses user-authenticated installation APIs; do not use the Actions `GITHUB_TOKEN` or an App installation token. Create/install the Apps and create the repositories separately as bootstrap prerequisites, then import the repositories into Terraform.
2. Ensure the S3 bucket named in `backend.hcl` already exists and is configured for private, encrypted, versioned state. Initialize and import the existing repositories:

   ```sh
   cd terraform
   terraform init -backend-config=backend.hcl
   terraform import 'github_repository.managed["repo-one"]' repo-one
   terraform import 'github_repository.managed["repo-two"]' repo-two
   terraform plan
   ```

   Import every repository declared in `terraform.tfvars` before applying. Review the plan; use `terraform apply` only when the proposed repository changes and app grants are intended.
3. Inspect managed resources and their current configuration with:

   ```sh
   terraform state list
   terraform show
   ```

   The state may contain sensitive information. Keep it in the secured backend, not in Git or artifacts.

## GitHub Actions

Configure repository/organization Actions variables from the values in `terraform.tfvars`: `GITHUB_ORGANIZATION`, `TF_REPOSITORIES`, `TF_APP_INSTALLATIONS`, and `TF_PROTECTED_BRANCHES` (the three `TF_*` values are JSON objects). Configure `TF_STATE_BUCKET`, `TF_STATE_KEY`, and `AWS_REGION`, plus `TF_PLAN_ROLE_ARN` and `TF_APPLY_ROLE_ARN`. Store the user token as the `TERRAFORM_GITHUB_TOKEN` Actions secret. AWS roles use OIDC; constrain plan trust to the repository's `pull_request` subject and apply trust to the `production` environment. Require reviewers for that environment and allow deployments from protected `main` only.

`.github/workflows/terraform.yml` always formats and validates. Same-repository PRs with remote-state settings run `terraform plan`; fork PRs do not receive AWS credentials and run validation only. A push to `main` runs `terraform apply` after validation. The local composite action `.github/actions/terraform-remote-state` handles OIDC authentication and S3 backend initialization for both jobs. It does not migrate state or create AWS resources.

## Change access through a pull request

In `app_installations`, each App maps to its installation ID and an explicit set of repository names. To narrow an App's access, remove a repository from that set; to add access, add a repository. For example:

```hcl
app_alpha = {
  installation_id = 11111111 # Replace with the real installation ID.
  repositories    = ["repo-two"] # Removing repo-one revokes that grant.
}
```

Submit the change as a PR and review the plan for only the intended grant additions/removals before merge. Do not change access directly in GitHub as the normal workflow. GitHub does not let this provider remove selected repositories while an installation is in **All repositories** mode; configure the installation as selected-repository access first, reviewing the impact in GitHub.

## Governance design

- **Ownership:** Assign every installed App a technical owner and business/service owner. Keep the owner, purpose, data scope, and renewal date with the access request or an organization inventory.
- **Review and expiry:** Require App-owner and repository-owner review for access changes. Record a time-bounded approval; review grants quarterly and remove expired or unused access through a PR.
- **Unknown installations:** Periodically compare organization-installed Apps and each installation's repository selection with the approved inventory and Terraform declarations. For example, `gh api --paginate "/orgs/$GITHUB_ORGANIZATION/installations" --jq '.installations[] | [.app_slug, (.id|tostring), .repository_selection] | @tsv'` lists org installations. Investigate unknown Apps and broad `All repositories` installations with the owner/security team; preserve an audit record and revoke only through an approved change.
- **Safe decommissioning:** Remove repository grants through a PR and apply; verify access is gone; then uninstall the App in GitHub if no repositories still need it. Remove its inventory/ownership record after evidence and retention requirements are satisfied. Repository resources have `prevent_destroy` to avoid accidental deletion.
- **Scale:** This exercise models a small number of repositories and Apps. At organization scale, use a central ownership/expiry inventory and scheduled drift reports or PRs rather than provisioning a large simulated estate or automatically revoking unknown access.

## Security and scope

Use least-privilege GitHub and AWS roles. Keep tokens in secret storage and restrict state bucket access; state can contain sensitive data. Enable S3 versioning, encryption, public-access blocking, and native lockfiles (`use_lockfile = true`, Terraform 1.10+).

For an existing local state, back it up securely before moving it and run `terraform init -migrate-state -backend-config=backend.hcl` only after confirming the bucket/key and reviewing the migration prompt. CI never migrates state.

This is a homework-scale proposal, not an enterprise rollout. It does not create GitHub Apps, the initial repositories, AWS roles, or the S3 bucket; those prerequisites are configured separately and the existing repositories are imported. No real organization IDs, installation IDs, tokens, or AWS account/bucket values are supplied. `terraform/terraform.tfvars.example` and `terraform/backend.hcl.example` contain placeholders only.
