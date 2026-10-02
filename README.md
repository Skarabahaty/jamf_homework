# GitOps-managed GitHub App governance

This repository is a deliberately safe starter for governing GitHub App access with Terraform. It does not contain an organization name, token, repository ID, or installation ID. Operators supply those values through variables and GitHub Actions configuration.

## What is managed

- `github_repository.managed` manages settings for at least two existing repositories. The `prevent_destroy` lifecycle rule makes accidental repository deletion fail closed.
- `github_app_installation_repository.access` is the authoritative allow-list for at least two GitHub App installations. A grant exists only when the app name and repository appear together in `app_installations`.
- `github_branch_protection.main` manages the protected branch policy where configured.
- `.github/workflows/terraform.yml` runs formatting, validation, and a plan for pull requests. A merge to `main` runs the same gate and applies from the protected `production` environment.

## Bootstrap

1. Copy `terraform/terraform.tfvars.example` to a local, ignored `terraform/terraform.tfvars`, replace placeholders with approved values, and provide `TF_VAR_github_token` through a short-lived token or CI secret. Never commit the copy.
2. Ensure the token has the minimum required organization/repository permissions for the provider and that the GitHub App installations already exist.
3. Initialize and import the existing repositories:

   ```shell
   cd terraform
   terraform init
   terraform import 'github_repository.managed["platform-infrastructure"]' platform-infrastructure
   terraform import 'github_repository.managed["service-catalog"]' service-catalog
   terraform plan
   ```

   Import every declared repository before the first apply. Resolve drift in a pull request; do not edit settings manually to make a plan pass.
4. Set these repository or organization Actions variables: `GITHUB_ORGANIZATION`, `TF_REPOSITORIES`, `TF_APP_INSTALLATIONS`, and `TF_PROTECTED_BRANCHES`. The three `TF_*` values are JSON representations of the corresponding maps in `terraform.tfvars.example`; keeping them as nonsecret Actions variables makes the plan input visible and reviewable without committing organization-specific names. Set `GITHUB_TOKEN` as a secret and configure the `production` environment with required reviewers. A dedicated token stored as an organization secret is preferred for applying organization-level changes.

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
