# Manual Steps After the Pipeline Runs

This file lists **everything that must be done by hand** after the
CodePipeline/CodeBuild run finishes successfully. Terraform only provisions
infrastructure — it deliberately does not create the first Coolify user,
does not register the runtime servers, and does not create the optional
API token. Do these in order.

You will need `terraform-outputs.json` (produced by the pipeline as a build
artifact) open in front of you — it has every IP address referenced below.

---

## 1. Log in and create the first admin account

1. Open `http://<control_plane_public_ip>:8080` (from `terraform-outputs.json`
   → `control_plane_public_ip`). Your own IP must match the `admin_ssh_cidr`
   value used for this deployment, or the Security Group will block you.
2. Coolify shows its own first-run registration screen since no user exists
   yet. Create the account yourself.
3. **Keep these credentials privately** — they are never stored in this
   repo, in Secrets Manager, or anywhere in AWS by this pipeline.

## 2. (Optional) Create an API Token

Only needed if you plan to automate anything against this Coolify instance
later (chatbots, external scripts, CI triggers, etc.).

1. Dashboard → **Security → API Tokens**.
2. Create a token with **Read + Write + Deploy** permissions — not **Root**.
3. If you want it available to future automation via AWS, store it yourself:
   ```bash
   aws secretsmanager create-secret \
     --name coolify/api-token \
     --secret-string "<paste the token here>" \
     --region <your-region>
   ```
   This step is manual on purpose — Terraform has no way to know this value
   in advance, since Coolify itself generates it after first login.

## 3. Download each runtime server's private SSH key

Terraform generated one independent key per runtime server and stored each
one in Secrets Manager, under a name shown in `terraform-outputs.json` →
`runtime_ssh_key_secret_names` (e.g. `coolify/ssh-keys/runtime-2`).

**On macOS/Linux:**
```bash
aws secretsmanager get-secret-value \
  --secret-id coolify/ssh-keys/runtime-2 \
  --query SecretString --output text \
  --region <your-region> > runtime-2.pem
chmod 600 runtime-2.pem
```

**On Windows/PowerShell** (this exact form matters — see the warning below):
```powershell
aws secretsmanager get-secret-value `
  --secret-id coolify/ssh-keys/runtime-2 `
  --query SecretString --output text `
  --region <your-region> | Out-File -FilePath runtime-2.pem -Encoding ascii
```

> ⚠️ **Do not** pipe through a `$variable` and redirect with `>` on
> PowerShell — that writes UTF-16 and silently corrupts the key. Always use
> `Out-File -Encoding ascii` (and never add `-NoNewline`; the key needs a
> real trailing newline).

If SSH later reports **"bad permissions"** on Windows:
```powershell
icacls runtime-2.pem /inheritance:r
icacls runtime-2.pem /grant:r "$($env:USERNAME):(R)"
```

Repeat for every name listed in `runtime_ssh_key_secret_names` (by default:
`runtime-2`, `runtime-3` — add more lines here yourself if you scaled the
`runtime_server_names` variable, see the main README's "Scaling" section).

## 4. Register each runtime server in Coolify

For **each** runtime server:

1. Dashboard → **Security → Private Keys** → paste the `.pem` contents you
   just downloaded.
2. Dashboard → **Servers → New Server**:
   - **IP**: use the server's **private** IP from `terraform-outputs.json`
     → `runtime_private_ips` (not the public one — Coolify connects to it
     from the Control Plane, which sits inside the same VPC).
   - **SSH user**: `ubuntu` — **not** `root`. This Ubuntu AMI blocks direct
     root login over SSH.
   - **Private Key**: the one you just added in step 1.
3. Once the server validates as reachable, open that server →
   **Connection** tab → set **Wildcard Domain** to
   `https://<that server's own public/Elastic IP>` (from
   `runtime_public_ips` in the outputs). Without this, Coolify defaults to
   generating `*.sslip.io` URLs from the server's *private* IP, which is
   unreachable from outside the VPC — apps will deploy successfully but be
   unreachable in the browser.

## 5. Set the production domain (once you have one)

1. Dashboard → **Settings → General → URL** → set your real domain.
2. Edit `compose/docker-compose.yml` on the Control Plane: switch the
   `coolify` service from the direct `8080:8080` port mapping to the
   commented-out Traefik `labels:` block already present in that file, then
   `docker compose up -d` again to apply it.

## 6. Delete the downloaded `.pem` files when you're done

They exist only on your local machine as a bridge between Secrets Manager
and the Coolify GUI. Once every server is registered (step 4), delete the
local copies — the keys remain permanently retrievable from Secrets Manager
if ever needed again.

---

## Quick checklist

- [ ] Logged in, created admin account, saved credentials privately
- [ ] (optional) Created API token, stored as `coolify/api-token` if needed
- [ ] Downloaded a `.pem` for every server in `runtime_server_names`
- [ ] Registered every runtime server (private IP, user `ubuntu`)
- [ ] Set Wildcard Domain on every runtime server (its own public/Elastic IP)
- [ ] Set production domain in Dashboard once decided
- [ ] Deleted local `.pem` files after use
