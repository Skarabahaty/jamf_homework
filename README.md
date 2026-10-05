# GitOps-managed GitHub App governance

This repository is a deliberately safe starter for governing GitHub App access with Terraform. It does not contain an organization name, token, repository ID, or installation ID. Operators supply those values through variables and GitHub Actions configuration.

## What is managed

- `github_repository.managed` manages settings for at least two existing repositories. The `prevent_destroy` lifecycle rule makes accidental repository deletion fail closed.
- `github_app_installation_repository.access` is the authoritative allow-list for at least two GitHub App installations. A grant exists only when the app name and repository appear together in `app_installations`.
- `github_branch_protection.main` manages the protected branch policy where configured.
- `.github/workflows/terraform.yml` runs formatting, validation, and a plan for pull requests. A merge to `main` runs the same gate and applies from the protected `production` environment.

## Bootstrap

1. Copy `terraform/terraform.tfvars.example` to a local, ignored `terraform/terraform.tfvars`, replace placeholders with approved values, and provide `TF_VAR_github_token` through a user-authenticated token. Never commit the copy.
2. Copy `terraform/backend.hcl.example` to ignored `terraform/backend.hcl` and fill in the approved, existing S3 bucket name and AWS region. Do not add AWS access keys to this file. The state bucket must be created and secured separately by the AWS platform team before backend initialization; this Terraform configuration does not create AWS resources.
3. Ensure the GitHub token has the minimum required organization/repository permissions for the provider and that the GitHub App installations already exist.
4. Initialize and import the existing repositories:

   ```shell
   cd terraform
   terraform init -backend-config=backend.hcl
   terraform import 'github_repository.managed["platform-infrastructure"]' platform-infrastructure
   terraform import 'github_repository.managed["service-catalog"]' service-catalog
   terraform plan
   ```

   Import every declared repository before the first apply. Resolve drift in a pull request; do not edit settings manually to make a plan pass.
5. Set these repository or organization Actions variables: `GITHUB_ORGANIZATION`, `TF_REPOSITORIES`, `TF_APP_INSTALLATIONS`, `TF_PROTECTED_BRANCHES`, `TF_STATE_BUCKET`, `TF_STATE_KEY`, and `AWS_REGION`. The three `TF_*` values are JSON representations of the corresponding maps in `terraform.tfvars.example`. Set `TF_PLAN_ROLE_ARN` and `TF_APPLY_ROLE_ARN` to the separately scoped AWS IAM role ARNs, and configure GitHub's OIDC provider and each role's trust policy for this repository. The plan role trust should accept only this repo's `pull_request` subject; the apply role is bound to the `production` GitHub environment subject, with that environment restricted to the protected `main` branch and required reviewers. The plan role needs state-object read and bucket listing permissions plus get/put/delete on only the corresponding `.tflock` object; it must not write the state object. The apply role needs state-object read/write and lock-object permissions, scoped to the configured key. Set `TERRAFORM_GITHUB_TOKEN` as a GitHub Actions secret and configure the `production` environment with required reviewers. Never store AWS access keys in GitHub variables or repository files.

`TERRAFORM_GITHUB_TOKEN` must be a user-authenticated token belonging to an account that can administer all governed repositories and manage the relevant organization App installations. For a fine-grained PAT, grant the minimum required repository administration permissions (including Administration: write for branch protection/settings) and ensure it is authorized for the organization. The `github_app_installation_repository` provider resource reads `/user/installations/{id}/repositories` and is not compatible with GitHub App installation authentication. Do not set it to the workflow's built-in `GITHUB_TOKEN` or an App installation token. Keep this token in Actions secrets, not variables.

### Troubleshooting GitHub API access

- `Resource not accessible by integration` while refreshing `github_branch_protection` means the Terraform credential lacks repository administration access. Confirm `TERRAFORM_GITHUB_TOKEN` is a user token with administration permissions and organization approval; expanding the workflow's built-in `GITHUB_TOKEN` permissions is not a substitute.
- A 404 for `GET /user/installations/<id>/repositories` can mean that the credential is an installation token rather than the required user-authenticated token, the token's user cannot access that installation, or the installation ID is wrong. Verify the ID in the target organization and verify the token user's access to that installation. Do not remove the Terraform resource or ignore the read error to force an apply.

## S3 remote state

`terraform/versions.tf` declares an S3 backend with no hard-coded values; Terraform backend configuration cannot use normal Terraform variables. For local use, supply the ignored `backend.hcl` file with `terraform init -backend-config=backend.hcl`. The example uses S3 native lockfiles (`use_lockfile = true`), which requires Terraform 1.10 or newer. CI builds a short-lived backend config from `TF_STATE_BUCKET`, `TF_STATE_KEY`, and `AWS_REGION`; it uses AWS OIDC via `TF_PLAN_ROLE_ARN` or `TF_APPLY_ROLE_ARN` rather than long-lived AWS credentials. No account ID, bucket name, role ARN, or credentials are included in this repository.

The PR check always formats and validates without contacting a backend. The authenticated remote-state plan runs only for same-repository pull requests when the bucket, key, region, and plan role variables exist; fork PRs do not receive AWS OIDC credentials and therefore get validation but no live remote plan. This is intentional: backend planning requires AWS access and S3 lockfile writes, so the plan role is limited to reading state and creating/removing the lock object, not writing state. Treat same-repository PR authors and workflow changes as trusted, and constrain AWS OIDC trust to the exact repository and `pull_request` subject. GitHub job permissions remain `contents: read` plus `id-token: write` solely on the authenticated plan/apply jobs; PR jobs have no GitHub contents or pull-request write permission. `id-token: write` only permits requesting a short-lived OIDC assertion; it does not grant GitHub repository write access. Until these AWS settings are configured, remote PR plans cannot run and a main-branch apply fails clearly rather than silently using local state.

Before adopting remote state for an existing local workspace:

1. Have the AWS platform team create the bucket separately with versioning enabled, server-side encryption, public access blocked, and narrowly scoped IAM. Keep the state object and lock object private; state may contain sensitive metadata even when provider credentials are marked sensitive.
2. Back up the current state securely outside Git (for example, `terraform state pull` into an access-controlled location) and verify the backup. Confirm the target bucket/key is correct and the bucket is empty or contains this exact workspace's state.
3. From `terraform/`, migrate deliberately with `terraform init -migrate-state -backend-config=backend.hcl`, review Terraform's migration prompt and completion output, then run `terraform state list` and `terraform plan`. Do not use `-force-copy` to bypass a warning or overwrite unrelated state.
4. Enable/version the bucket's recovery process and test restoration. Keep prior state versions according to policy; never delete a state version or lock object manually to resolve a lock without investigating the active run first.

For a new workspace with no local state, use `terraform init -backend-config=backend.hcl` instead (no `-migrate-state`). CI only initializes an already-migrated remote backend and never migrates state. Do not run `apply`, migration, or create AWS resources as part of preparing this repository.

## Ownership and review

The platform/infrastructure team owns `terraform/` and the workflow. A change requires two CODEOWNERS-approved reviewers (or the organization equivalent), including an app owner for access changes. Pull requests must include the plan and explain the business owner, requested scope, and expiry/review date. Branch protection prevents direct changes to `main`; the workflow is the only supported apply path.

Every App access grant must have a named business owner and a review date in the pull request. Reconfirm grants quarterly and remove unused access immediately. If an exception is necessary, record the exception and its expiry in the PR rather than weakening the global policy.

## Narrowing and removing access

Access is set-based, so the diff is intentionally easy to audit. For example, to narrow `security-scanner` from both repositories to one:

```hcl
security-scanner = {
  installation_id = 11111111
  repositories    = ["service-catalog"]
}
```

To remove the app entirely, delete its map entry. The plan must show the corresponding `github_app_installation_repository.access["security-scanner:platform-infrastructure"]` (and any other grant) being destroyed. Review that destroy before merge; do not use `-target` to bypass it. For a repository transfer or decommission, first remove all App grants in one PR, verify the plan, then remove it from `repositories` in a separately approved PR.

## Unknown-install detection

Terraform intentionally manages the approved allow-list; it cannot make an unapproved installation disappear. On a scheduled audit, an organization administrator should compare the live installation list with this configuration:

```shell
gh api --paginate "/orgs/${GITHUB_ORGANIZATION}/installations" \
  --jq '.installations[] | [.app_slug, .id, (.repository_selection // "all")] | @tsv'
```

Investigate any installation that is not represented in `app_installations`, any installation with `repository_selection=all`, and any repository access not represented by a desired grant. Revoke unknown installations through GitHub organization settings or the API after incident review, then add the finding and remediation to the audit record. A scheduled external audit can open a PR when it detects drift; it must not auto-revoke access.

## Security and operations

- Use GitHub Actions OIDC or short-lived credentials where available; otherwise use a fine-grained token with only required repository/organization administration permissions. Store it as an Actions secret, never in tfvars, state committed to Git, logs, or PR text.
- Use a remote, encrypted Terraform backend with locking in production. Review the provider plan as sensitive change control; restrict state access because provider state can contain metadata.
- Keep `terraform.lock.hcl` under review after generating it with `terraform init`. Dependabot or an equivalent process should update the GitHub provider.
- Treat provider/API failures as failed changes. Do not turn off branch protection or ignore a failed apply.
- On suspected compromise: pause applies, revoke the affected installation/token, preserve the plan and audit logs, rotate credentials, and use a reviewed PR to restore the intended allow-list.

## Safe decommissioning

1. Open a PR removing the App's repository entries and wait for the destroy plan to be reviewed.
2. Merge and verify the apply plus the live installation audit.
3. Remove repository protection/settings management only after ownership transfers and retention requirements are recorded.
4. Destroy Terraform state only through the approved retention process. Never delete the GitHub repository from this configuration; `prevent_destroy` is a deliberate safety net.
