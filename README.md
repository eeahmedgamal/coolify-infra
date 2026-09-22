# Coolify Infra — Production

Deploys Coolify on 3 EC2 instances (1 Control Plane + 2 Runtime/deployment
servers), pulling Coolify's own images from a **private ECR** instead of
Docker Hub. `coolify-db` and `coolify-redis` are **not** used — replaced by
**Amazon RDS (PostgreSQL)** and **Amazon ElastiCache (Redis)**.

Defaults to `us-east-1`, but the region is a variable (`var.aws_region`) -
Availability Zones and the AMI are both auto-detected at apply time, so
changing the region only requires updating one value (see "Changing the
Region" below), except for one Terraform limitation noted there.

Everything below the network/servers/data layer is provisioned automatically
by this repo's Terraform + AWS CodePipeline. A small number of steps are
intentionally manual — they are called out explicitly.

**Full architecture diagram:** [`docs/architecture.svg`](./docs/architecture.svg)
— every subnet, security group, IAM role, secret, and traffic path (pipeline,
admin dashboard access, public app traffic, and internal deploy traffic)
in one picture.

## Prerequisites

- An AWS account with permission to create VPCs, EC2, RDS, ElastiCache, IAM
  roles, and Secrets Manager secrets.
- The 4 ECR repositories already created, with Coolify's own images already
  mirrored into them (manual, one-time - see "What Is Manual" below).
- An S3 bucket for Terraform state (referenced in `provider.tf`'s `backend`
  block). **S3 bucket names are unique across all of AWS, not just your
  account** — `coolify-terraform-state` is very likely already taken by
  someone else. Pick your own name (e.g. including your account ID) before
  running this the first time, create it, and update `provider.tf`'s
  `backend "s3" { bucket = "..." }` line to match — this is a manual,
  by-hand edit on purpose (see "Changing the Region" below for why the
  `backend` block can't use a variable at all):
  ```bash
  aws s3 mb s3://coolify-terraform-state-<your-account-id> --region us-east-1
  ```
  Versioning is intentionally left disabled - a single Terraform state
  file doesn't need version history the way application data does, and
  this avoids accumulating old state versions (and their storage cost)
  over repeated `apply`/`destroy` cycles.
- Terraform >= 1.6.

## Quick Start

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`
   and fill in `account_id`, `admin_ssh_cidr`, and `tag_owner` (all required,
   no defaults - see "Resource Tagging" below for what `tag_owner` is for).
   `terraform.tfvars` is `.gitignore`d — **never commit it**, even with
   placeholder-looking values, since it's the file real values land in.
2. For a local dry run: `cd terraform && terraform init && terraform plan`.
3. For the real pipeline, **don't reuse `terraform.tfvars` for this** — set
   the same three values as CodeBuild environment variables instead (see
   "Running the Pipeline" below) and trigger it. This is why the pipeline
   never reads `terraform.tfvars` at all: two different mechanisms for two
   different audiences (a person running Terraform from their own machine,
   vs. the pipeline), neither of which touches git.
4. Create the Terraform state S3 bucket by hand once, with a name that is
   **globally unique across all of AWS** — not just your account (S3 bucket
   names are a global namespace). `coolify-terraform-state` in
   `provider.tf` is a placeholder; if it's already taken by anyone else,
   pick your own (e.g. `coolify-terraform-state-<your-account-id>`) and
   update the `bucket` value in `provider.tf`'s `backend "s3"` block to
   match before running `terraform init` for the first time. See
   "Prerequisites" below for the exact `aws s3 mb` command.

## Repository Layout

```
coolify-infra/
├── README.md
├── buildspec.yml                 # CodeBuild: terraform init/plan/apply
├── .gitignore
├── terraform/
│   ├── provider.tf
│   ├── variables.tf
│   ├── network.tf                # VPC, public+private subnets, IGW, routes
│   ├── security-groups.tf        # least-privilege SGs for every component
│   ├── iam.tf                    # instance roles/profiles
│   ├── rds.tf                    # PostgreSQL (single-AZ, TLS enforced server-side, 7-day backups)
│   ├── elasticache.tf            # Redis (no TLS/AUTH - see Known Issues Resolved)
│   ├── control-plane.tf          # EC2 #1 + Elastic IP
│   ├── runtime-servers.tf        # EC2 #2/#3 + Elastic IPs + per-server SSH keys
│   ├── outputs.tf
│   └── control-plane-iam-policy.reference.json
├── compose/
│   ├── docker-compose.yml        # Coolify stack, images sourced from ECR
│   └── .env.template
└── scripts/
    └── install-coolify.sh.tftpl      # rendered into EC2 #1's user-data by Terraform
```

## What Is Fully Automated

Running this repo's pipeline provisions, end to end:
- A new isolated VPC, public subnets (Control Plane + Runtime, each with an
  Elastic IP) and private subnets (RDS + ElastiCache).
- Security groups scoped per component (nothing is open more broadly than
  it needs to be — see `security-groups.tf`).
- RDS PostgreSQL (single-AZ for now) and ElastiCache Redis (SG-restricted,
  no TLS/AUTH - see "Known Issues Resolved" for why).
- EC2 #1, fully installing and starting Coolify from ECR images, already
  pointed at RDS/ElastiCache, with database migrations run automatically,
  and all infrastructure secrets (DB password, the Laravel APP_KEY)
  auto-generated by Terraform and injected from Secrets Manager. Reachable
  immediately at `http://<control-plane-public-ip>:8080` for first login.
- EC2 #2 and #3, with Docker installed and their own individual SSH keys
  (never shared between servers).

## What Is Manual (by design, and that's fine)

1. **Pulling and pushing the Coolify images to ECR** — done by hand, before
   running this pipeline for the first time. Source images:
   `ghcr.io/coollabsio/coolify`, `coollabsio/coolify-realtime` (Docker Hub),
   `ghcr.io/coollabsio/sentinel` (GHCR only - no Docker Hub copy exists),
   and the official `traefik` image. Push into repos named exactly
   `coolify/coolify`, `coolify/coolify-realtime`, `coolify/sentinel`,
   `coolify/traefik` - the compose file expects these exact paths.
2. **Creating the ECR repositories themselves** — also done by hand, before
   the pipeline runs (same 4 names as above).
3. **Every step after the pipeline finishes** — creating the first admin
   account, the optional API token, downloading SSH keys, registering the
   runtime servers, and setting the production domain. These are
   intentionally not automated (Terraform provisions infrastructure, not
   application-level accounts). **See the dedicated
   [`MANUAL-STEPS.md`](./MANUAL-STEPS.md)** for the exact, ordered
   walkthrough — including the Windows/PowerShell key-download gotcha and
   the Wildcard Domain step that's easy to miss.
4. **The CodePipeline/CodeBuild project itself** — like any pipeline, it
   needs to be created once (console or a small separate bootstrap script)
   before it can run this repo's `buildspec.yml`.
5. **Creating the GitHub App for deployments** — use a dedicated
   Organization created for this purpose (not a shared/personal one -
   creating a GitHub App requires Owner-level access on the Organization,
   not just Admin on individual repos). When registering it in Coolify
   (Sources -> New GitHub App), the "Instance endpoint" field must use
   **port `8080`, not the `8000` Coolify suggests by default** - `8080` is
   the actual port this stack's Dashboard listens on. When installing the
   App on GitHub, choose "Only select repositories" and grant it access to
   the specific deployment repos only - never "All repositories".

## Scaling: Adding or Removing a Runtime Server

This is a one-line change, deliberately made this easy from the start.
Every runtime server (its EC2 instance, Elastic IP, individual SSH key, and
Secrets Manager entry) is generated from a single Terraform `for_each` over
one variable — `runtime_server_names` in `terraform/variables.tf`:

```hcl
variable "runtime_server_names" {
  default = ["runtime-2", "runtime-3"]
}
```

**To add a server:** add a name to the list (e.g.
`["runtime-2", "runtime-3", "runtime-4"]`), commit, push, and re-run the
pipeline. Terraform creates only the new instance, its own SSH key, and its
own Elastic IP — the existing two servers are untouched (Terraform diffs
against state; see the Changelog's "Not a bug" note on this). Then follow
[`MANUAL-STEPS.md`](./MANUAL-STEPS.md) steps 3–4 for the one new server
only (download its key, register it, set its Wildcard Domain).

**To remove a server:** delete its name from the list, commit, push, and
re-run the pipeline. Terraform will plan to *destroy* that one instance, its
Elastic IP, its SSH key pair, and its Secrets Manager entry — review the
`terraform plan` output before approving if running locally, since this is
a destructive change (any apps still deployed on that specific server will
go down with it; move them first via the Coolify Dashboard if needed).
Also remove the server from Coolify's own **Servers** list in the Dashboard
(Terraform has no visibility into that application-level registration).

**What you never need to touch for this:** `control-plane.tf`,
`network.tf`, `security-groups.tf`, `rds.tf`, `elasticache.tf` — none of
them reference specific server names; they scale automatically with the
list.

## CodeBuild's IAM Role

CodeBuild needs its own IAM Role - separate from the EC2 instance roles in
`iam.tf` - to run `terraform apply` at all (it has to create the VPC, EC2
instances, RDS, IAM roles, etc.). This role is created once, by hand,
**before** the pipeline can run at all (Terraform can't create the very
role it needs to run under - a bootstrapping limitation, not a choice).

Rather than attaching broad AWS managed policies (`AmazonEC2FullAccess`,
`IAMFullAccess`, etc.), attach **only** the least-privilege policy in
`terraform/codebuild-iam-policy.reference.json` instead. It scopes:

> 🔴 **Audit this now if the role already exists.** While first debugging
> this pipeline, the following AWS-managed `*FullAccess` policies ended up
> attached to `coolify-codebuild-role` **at the same time as** the
> least-privilege custom policy below — which defeats the entire point of
> it, since IAM grants the union of every attached policy:
> `AmazonEC2FullAccess`, `AmazonElastiCacheFullAccess`,
> `AmazonRDSFullAccess`, `AmazonS3FullAccess`, `AmazonVPCFullAccess`,
> `CloudWatchLogsFullAccess`, `IAMFullAccess`, `SecretsManagerReadWrite`.
> **Detach every one of these from the role**, leaving only
> `CodeBuildBasePolicy-coolify-codebuild-role-<region>` (the custom policy
> below, which already includes everything the pipeline actually needs —
> confirmed by a full successful `apply` with only this policy attached).
> After detaching, re-run the pipeline once to confirm nothing regresses
> to an `AccessDenied` error; if something does, add the specific missing
> action to the custom policy — never re-attach a `*FullAccess` policy as
> the fix.
- IAM, Secrets Manager, RDS, and ElastiCache actions to resources whose
  name/ARN starts with `coolify-` (matching this repo's naming
  convention) instead of the whole account.
- S3 to only the Terraform state bucket.
- New EC2/VPC/security-group resources to ones tagged `product=coolify`
  (a hard `Deny` blocks creating any that aren't tagged that way).

Some EC2/VPC actions genuinely don't support resource-level ARNs in IAM at
all (a real AWS limitation, not something this repo can work around) -
those are scoped by the tag condition instead, which is why the `Deny`
statement matters as a backstop.

This policy has been audited action-by-action against every resource and
data source this Terraform config actually creates or reads, including
two easy-to-miss ones: `ec2:ModifySubnetAttribute` (needed because the
public subnets set `map_public_ip_on_launch = true`) and an
`arn:...:snapshot:coolify-*` resource pattern for RDS (needed because
destroying the database creates a final snapshot, which is a different
ARN resource type than the database itself).

## Running the Pipeline

1. **On the CodeBuild project itself**, set the "Build image" to
   `hashicorp/terraform:1.7.5` (or your pinned version) instead of a
   generic Ubuntu/Amazon Linux image - see "Network Egress / Air-Gapped
   Pipeline" below for why.
2. Add these as Environment Variables on the same CodeBuild project
   (plaintext, not secrets - they aren't sensitive) before the first run:
   - `TF_VAR_account_id` = your AWS account ID (12 digits) - required, no default.
   - `TF_VAR_admin_ssh_cidr` = your own IP in CIDR form (e.g. `203.0.113.4/32`) - required, no default.
   - `TF_VAR_tag_owner` = whoever is responsible for these resources (e.g. an email) - required, no default.
3. Trigger the pipeline (push to the repo, or run manually).
4. Once it finishes, complete manual steps 3 and 4 above.

## Network Egress / Air-Gapped Pipeline

By default, AWS CodeBuild has outbound internet access even without any
special configuration - so as written, this pipeline reaches the public
internet in **two** places, not just one:

1. Downloading the Terraform CLI itself (avoided already - see the note at
   the top of `buildspec.yml`: set the CodeBuild project's "Build image" to
   `hashicorp/terraform:<version>` instead of a generic image).
2. **`terraform init` downloading the `aws`/`tls`/`random` provider plugins
   from `registry.terraform.io`** - this happens on every single pipeline
   run, not just once, and is easy to overlook.

If a fully internet-free pipeline matters for your security posture, pick
one of these (in increasing order of effort):

- **Accept it, but log it**: leave CodeBuild outside your VPC (its default
  mode) and rely on the fact that its only external destinations are
  well-known HashiCorp/AWS domains over HTTPS. Simplest, and how most
  Terraform pipelines run in practice.
- **Restrict, don't eliminate**: run CodeBuild inside your VPC with a NAT
  Gateway, and use an egress allowlist (e.g. AWS Network Firewall or a
  proxy) permitting only `registry.terraform.io` and
  `releases.hashicorp.com`. Genuine internet access still exists, but
  narrowed to two specific domains instead of anything.
- **True zero internet**: run CodeBuild inside your VPC with **no** NAT
  Gateway at all, and add VPC Endpoints for every AWS service this
  pipeline actually calls (S3 for state, ECR, Secrets Manager, EC2, IAM,
  RDS, ElastiCache, STS, CloudWatch Logs). This covers all AWS API calls
  with zero internet exposure. The remaining gap - the Terraform provider
  plugins themselves - is solved with a private **filesystem mirror**: download
  the `aws`/`tls`/`random` provider plugins once, upload them to a private
  S3 bucket, and configure Terraform's CLI (`.terraformrc`) to use that
  bucket as a `filesystem_mirror` instead of the public registry. More
  setup effort, but achieves genuinely no public internet access anywhere
  in the pipeline.

## Changing the Region

`var.aws_region` defaults to `us-east-1` but can be overridden (e.g. via
`TF_VAR_aws_region` on CodeBuild, or in `terraform.tfvars` for local runs).
Availability Zones and the Ubuntu AMI are both auto-detected at apply time
for whatever region is set - no manual lookup needed for those.

**One exception:** the S3 backend's `region` in `provider.tf` cannot use a
variable at all - this is a hard limitation of Terraform's `backend` block
syntax, not something this repo can work around. If you deploy this to a
different region, update that one line by hand, or override it without
editing the file via:
```bash
terraform init -backend-config="region=<new-region>"
```

## Updating Coolify

There is no automatic update path once images are sourced from ECR — the
Dashboard's "Update" button is not used. To update: manually mirror the new
version to ECR (same manual process as the initial setup), update the
version variables in `terraform/variables.tf`, and re-run the pipeline.

## Resource Tagging

Every resource created by this Terraform automatically receives these tags
(via `default_tags` on the AWS provider - no per-resource repetition needed).
All three are variables (`tag_product`, `tag_environment`, `tag_owner`) -
`tag_owner` is required with no default, so every deployment explicitly
states who is responsible for it:

```
product:     coolify        (default - override via tag_product)
environment: production     (default - override via tag_environment)
owner:       <required>      (no default - must be set via tag_owner)
```

## Tearing Down and Rebuilding

**The RDS instance has `deletion_protection = true`.** AWS will refuse to
delete it — via `terraform destroy`, a plain `terraform apply` that would
recreate it, or a manual console deletion — while this is set. To actually
tear it down on purpose: edit `rds.tf`, set `deletion_protection = false`,
run `terraform apply` for that one change by itself, and only then run
`terraform destroy`. This is intentional friction against exactly the kind
of accidental deletion this flag exists to prevent — don't leave it set to
`false` afterward if you're not immediately destroying.

Every secret resource sets `recovery_window_in_days = 0`, so
`terraform destroy` deletes them immediately and permanently instead of
leaving them in AWS's default 30-day recovery window - without this, a
fresh `terraform apply` right after a `destroy` fails with
`"a secret with this name is already scheduled for deletion"` for every
one of the 9 secrets this repo creates. The RDS instance takes a final
snapshot on destroy, named uniquely per deployment via
`random_id.final_snapshot_suffix` (not a fixed name, which would collide
with a snapshot left over from a previous destroy; and not `timestamp()`,
which would cause a spurious "changed" diff on every single
`terraform plan` even when nothing else changed).

## Known Issues Resolved

This section covers application/runtime issues (Coolify itself, the EC2
`user_data` script). For **pipeline/CI issues** — CodeConnections
permissions, `buildspec.yml` working-directory gotchas, the AMI lookup
switch, and IAM policy gaps — see **[`CHANGELOG.md`](./CHANGELOG.md)**,
which documents every one hit while first wiring up the CodeBuild pipeline
itself, in the order they were found.

Real errors hit and fixed while first standing up this stack, kept here so
they aren't rediscovered from scratch on a future rebuild:

- **`AccessDeniedException ... ecr:GetAuthorizationToken`** during
  `install-coolify.sh.tftpl`'s first boot, even though the IAM policy in
  `iam.tf` clearly grants it - AWS IAM permissions can take anywhere from
  seconds to a few minutes to fully propagate after a role is created,
  especially when a role is recreated with the *same name* shortly after
  a previous `terraform destroy` (as happens when tearing down and
  rebuilding this stack for a fresh test). Fixed with a 10-attempt retry
  loop (15s apart) around the ECR login step, plus an explicit
  `depends_on` from the Control Plane instance to the IAM role policy
  resource so Terraform doesn't launch it any earlier than necessary.
- **`Found preexisting AWS CLI installation ... rerun with --update`**
  causing the whole script to abort (`set -euo pipefail`) if `user_data`
  is ever manually re-triggered on an instance where it partially ran
  before (e.g. while diagnosing the IAM propagation issue above, via
  `cloud-init clean && cloud-init init ...`). Fixed by checking
  `command -v aws` first and skipping the install entirely if already
  present, making the script safe to re-run.

- **`Cannot find version X for postgres`** on `terraform apply` - AWS
  RDS's available engine versions differ by account/region and change over
  time. Always verify with
  `aws rds describe-db-engine-versions --engine postgres --region <region> --query "DBEngineVersions[].EngineVersion" --output table`
  before trusting a hardcoded version string (including this repo's own
  default).
- **ElastiCache `AUTH token is only supported when encryption-in-transit is
  enabled`, immediately followed by `Modification of transit encryption is
  not supported for access control enabled clusters`** if you try the
  opposite change - AWS ties AUTH and transit encryption together and
  won't let you have one without the other, and won't let you toggle
  either in-place once AUTH has been set. This repo settled on **neither**
  (no TLS, no AUTH), relying on the Security Group alone, because this
  stack's Redis client doesn't support `rediss://`.
- **Coolify showing `relation "instance_settings" does not exist"`** on
  first load - a fresh RDS database has no schema until Laravel's
  migrations run; nothing runs them automatically here. Fixed by
  `install-coolify.sh.tftpl` now running `php artisan migrate --force`
  right after `docker compose up -d`.
- **`Failed to store SSH key: Unable to create a directory at
  .../storage/app/ssh/keys`** when adding a server's key from the
  Dashboard - the `coolify` container runs as a non-root user and needs
  its SSH storage directory pre-owned by that UID. Fixed by switching that
  volume to a bind mount (`/data/coolify/ssh`) that the install script
  `chown`s before first start (see the UID caveat in that script's
  comments).
- **App URLs unreachable (`ERR_CONNECTION_TIMED_OUT`) even though the
  deployment succeeded** - Coolify generated a `*.sslip.io` domain using
  the runtime server's *private* IP, which isn't routable from outside the
  VPC. Fixed per-server by setting its Wildcard Domain to its public/
  Elastic IP (see "What Is Manual", step 5).
- **`docker-sentinel` crash-looping on the Control Plane** - it requires
  `TOKEN` and `PUSH_ENDPOINT` env vars that this compose file never sets.
  Removed from the Control Plane entirely; it works correctly on runtime
  servers instead, where Coolify's own Dashboard toggle sets those vars
  for you.
- **`coolify-proxy`/`coolify-realtime` reporting `unhealthy` while working
  fine** - Traefik's healthcheck needed `--ping=true` and
  `--ping.entrypoint=http` explicitly (now added); `coolify-realtime`'s
  healthcheck was removed rather than guessed at further, since a wrong
  healthcheck causing a false "unhealthy" is worse than no healthcheck.

## Limitations

- The RDS/ElastiCache replacement of `coolify-db`/`coolify-redis` follows a
  community-documented technique, not an officially supported toggle in the
  Coolify UI. Re-verify `compose/docker-compose.yml` against the upstream
  file after every Coolify version upgrade.
- There is no native load balancing or automatic distribution of new
  deployments between the two runtime servers - this repo provisions the
  infrastructure only, not that selection logic.
- Auto Scaling is not included in this repo (it was deferred to a follow-up
  phase, since the current requirement is a fixed 3-server layout).
