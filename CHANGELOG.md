# Changelog — Pipeline Hardening Session

Every bug hit while first standing up this pipeline end-to-end, in the order
they were found, with the fix that's already applied in this repo. Kept here
so none of these get rediscovered from scratch on a future rebuild or by a
new team member.

## 1. `DOWNLOAD_SOURCE` failed — CodeConnections access denied
**Symptom:** `Failed to get access token from arn:aws:codeconnections:...`
**Cause:** The GitHub connection (AWS CodeConnections) was in a `Pending`
state — never fully authorized on the GitHub side.
**Fix:** Re-authorized the connection in *Developer Tools → Connections*
until it showed `Available`.

## 2. `BUILD` failed — `cd: terraform: No such file or directory`
**Symptom:** `terraform plan` failed in the `build` phase even though
`terraform init` succeeded in `pre_build`, using the identical `cd terraform`
command.
**Cause:** CodeBuild runs every phase's commands in **one continuous shell
session**. `pre_build`'s `cd terraform` left the working directory inside
`terraform/` for the *rest of the build* — so `build`'s `cd terraform`
tried to enter `terraform/terraform`, which doesn't exist.
**Fix:** `buildspec.yml` now uses the absolute path
`cd $CODEBUILD_SRC_DIR/terraform` on every single command, in every phase,
rather than relying on directory state carrying over between commands.

## 3. IAM role missing `codeconnections:UseConnection` permission
**Symptom:** Recurring `AccessDeniedException` on the CodeConnections ARN
even after step 1 was fixed.
**Cause:** The `coolify-codebuild-role`'s customer-managed policy had no
statement at all for `codeconnections`/`codestar-connections` actions.
**Fix:** Added a statement granting `GetConnectionToken`, `GetConnection`,
and `UseConnection` (both the new `codeconnections:*` and legacy
`codestar-connections:*` action names, since AWS renamed the service and
some SDKs still resolve the old name) scoped to the specific connection ARN.

## 4. `terraform plan` failed — `data.aws_ami.ubuntu` returned no results
**Symptom:** `Your query returned no results` while resolving the Ubuntu AMI
by name-pattern filter.
**Cause:** Canonical changed its AMI naming pattern between Ubuntu releases
(`hvm-ssd` → `hvm-ssd-gp3` from 24.04 onward) — a filter-by-name lookup is
inherently fragile against upstream naming changes.
**Fix:** Replaced the `data "aws_ami"` filter entirely with
`data "aws_ssm_parameter"`, reading Canonical's own officially published
SSM parameter (`/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id`).
This resolves directly to a real AMI ID and never depends on guessing a name
pattern again. See `network.tf`.

## 5. IAM role missing `ssm:GetParameter` for the AMI lookup
**Symptom:** `AccessDeniedException ... ssm:GetParameter` after fix #4 was
deployed.
**Cause:** The new data source needs read access to that specific SSM
parameter path, which wasn't in the policy yet.
**Fix:** Added an `SSMReadOnlyForAmiLookup` statement scoped to
`arn:aws:ssm:*::parameter/aws/service/canonical/*` (read-only, and scoped to
Canonical's own published parameters — not a broad `ssm:*`).

## 6. State drift — `AlreadyExists` on RDS, ElastiCache, and a subnet
**Symptom:** `terraform apply` failed on three unrelated resources at once:
`ReplicationGroupAlreadyExists`, `DBInstanceAlreadyExists`, and
`InvalidSubnet.Conflict` on the same CIDR.
**Cause:** An earlier `apply` (before fixes #2–#5 landed) had partially
succeeded in *creating real AWS resources* before failing on a later step —
so those resources existed in AWS but were never recorded in Terraform's
state file. Every subsequent `plan` still saw them as "to create."
**Fix:** Since these were empty resources from the failed early attempt (no
real data), they were deleted by hand in the AWS Console (RDS instance,
ElastiCache replication group, the duplicate subnet — after first
terminating an EC2 instance that had been launched into that subnet, which
was blocking the subnet deletion). `apply` then recreated them cleanly, this
time recorded correctly in state.
**Takeaway:** *This is not a discovered pipeline bug that needed a code
fix* — it's a one-time consequence of iterating on a broken pipeline. A
pipeline that already works end-to-end (this one, now) will not produce
this kind of drift on a normal, successful run.

## Not a bug — clarified for future readers

**Does every pipeline run redo everything from scratch?** No. Terraform is
idempotent: each run diffs the desired state (this repo's code) against the
actual recorded state (in the S3 backend) and only touches what changed. A
second run with no code changes reports `No changes.` and does nothing.

**How do I destroy everything?** See "Tearing Down and Rebuilding" in
`README.md` — short version: `terraform destroy` locally (not from
CodeBuild — the pipeline's IAM policy and `buildspec.yml` aren't wired for
destroy), which does **not** touch the state bucket, the CodeBuild project,
or CodeBuild's own IAM role — those are deleted separately, by hand, if
ever needed.
