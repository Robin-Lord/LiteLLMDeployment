# Setup Guide

This guide is the main deployment path. It keeps top-level flow and platform-specific steps in one document so setup is easy to follow without excessive file-hopping.

## Recommended architecture

- Neon PostgreSQL
- Hetzner Cloud VM
    - Ubuntu 24.04
    - Docker Compose
    - Tailscale on the VM
    - LiteLLM not published directly on the host
    - Caddy published only on the VM's Tailscale IP
    - agent listener on `:4000`
    - admin listener on `:4001`
    - LiteLLM UI accessed over Tailscale on `:4001/ui/`, with SSH tunnel available as an extra admin path

This gives you:

- central API control
- DB-backed model and key management
- no raw provider keys in agents
- revocable per-agent virtual keys
- a safer default network posture
- separate agent and admin entry points

## Before you start

You need accounts and tools that the guide does not cover setting up:

- a Hetzner Cloud account
- a Neon account
- Tailscale installed on your admin devices (the guide covers the VM install separately)
- an SSH key pair, with the public key already uploaded to your Hetzner account

## Top-level sequence

1. Create the Neon database and save the connection string.
2. Create the Hetzner VM and perform initial OS hardening.
3. Install Docker, Tailscale, and prepare the working directory.
4. Copy the repo templates to the VM and fill in `.env`.
5. Start LiteLLM with Docker Compose.
6. Access LiteLLM over Tailscale.
7. Add provider credentials, model aliases, and virtual keys in LiteLLM.
8. Give agents only the tailnet base URL and their LiteLLM virtual key.

## 1. Neon

Create a new Neon project and copy the PostgreSQL connection string.

Expected shape:

```text
postgresql://USER:PASSWORD@HOST/DBNAME?sslmode=require&channel_binding=require
```

Notes:

- Keep this as `DATABASE_URL`.
- For this setup, use Neon’s direct connection string, not the pooled / PgBouncer connection string.
- If the host contains `-pooler`, that is the pooled form and is not the one you want here.
- Do not put provider credentials in Neon manually; let LiteLLM manage its own DB state.
- The database is the control-plane state for models, credentials, virtual keys, and spend metadata.
- Prisma migrations during LiteLLM startup can hang or time out against pooled connection strings, so use the direct URL from the start.
- The database is not on your Tailscale network. Once the VM exists, restrict Neon access to the VM's public IP using Neon's IP allowlist (covered at the end of step 2).

## 2. Hetzner

In the Hetzner Cloud interface, create a new server. In this guide, “VM” and “server” mean the same thing.

Create the server with:

- Ubuntu 24.04
- your SSH key attached at creation
- ideally a second admin SSH key ready for backup access
- at least 4 vCPU / 8 GB RAM for a comfortable baseline
- public networking enabled
- a public IPv4 Primary IP attached
- IPv6 optional
- no Hetzner private network for this initial setup
- no Hetzner Cloud Firewall for the initial manual setup
- Cloud config left blank

“SSH key attached at creation” means selecting your public SSH key in the Hetzner server-creation flow so the server is key-accessible immediately and does not depend on password login.

If possible, authorize more than one admin key from the start so you are not depending on a single laptop.

Networking choices for this setup:

- keep the public network enabled
- attach a public IPv4 Primary IP even though it has a small extra charge
- do not rely on IPv6-only for the first deployment
- skip Hetzner private networking unless you later add multiple Hetzner servers that need to talk privately
- leave Hetzner Cloud Firewall unused for the initial deployment
- leave Cloud config blank unless you later automate bootstrap with cloud-init

Reasoning:

- the server needs normal outbound internet access for setup, Docker image pulls, package installs, Neon access, and Tailscale
- SSH (port 22) is left on the public interface intentionally — anyone can attempt to connect, but key-only auth means they cannot get in without a valid private key. The alternative (SSH only over Tailscale) creates a recovery problem: if Tailscale breaks, you lose SSH access and need the cloud provider's rescue console to recover
- Tailscale is already the private-access layer for LiteLLM
- IPv4 keeps connectivity and debugging simpler than an IPv6-only setup
- using only UFW at first avoids debugging two firewall layers while bringing up SSH and Tailscale
- Cloud config is useful for automation, but unnecessary for the first manual deployment

SSH in as root once:

```bash
ssh root@YOUR_SERVER_IP
```

Create the operator user:

```bash
adduser litellm
usermod -aG sudo litellm
mkdir -p /home/litellm/.ssh
chmod 700 /home/litellm/.ssh
touch /home/litellm/.ssh/authorized_keys
chmod 600 /home/litellm/.ssh/authorized_keys
chown -R litellm:litellm /home/litellm/.ssh
```

Then add your public key to `/home/litellm/.ssh/authorized_keys`.

Rules:

- put public keys in this file, never private keys
- use one public key per line
- if you have a second admin key, add that public key on its own line as well

If you already have the current root user’s `authorized_keys` populated and want the quickest path, you can append those same public key lines into `/home/litellm/.ssh/authorized_keys`.

Reconnect as that user:

```bash
ssh litellm@YOUR_SERVER_IP
```

Before hardening SSH further, verify both of these work:

```bash
sudo -i
exit
ssh litellm@YOUR_SERVER_IP
```

Only disable direct root SSH login after you have confirmed the `litellm` user can log in and can run `sudo`.

Before you move on, make sure all of these are true:

- your SSH private key has a passphrase
- the passphrase is stored in your password vault
- the private key is backed up in encrypted form
- ideally a second admin key is already authorized on the server

See [SSH Backups](ssh-backups.md) for the recovery/access guidance.

Now that the VM has a public IP, restrict Neon to it:

1. Copy the VM's public IPv4 address from the Hetzner dashboard.
2. In Neon, add that IP to the project's IP allowlist.
3. If you need direct DB access from your laptop (`psql` or a DB tool), add your laptop's public IP too.

## 3. Server bootstrap

This repo includes a bootstrap script for Ubuntu 24.04:

- [bootstrap-ubuntu.sh](/Users/robin/Dropbox/Distilled%20backup/Sync/Personal/Creative/2026%2004%20(April)%20LiteLLM/remote-server-instructions/scripts/bootstrap-ubuntu.sh)

Copy it to the server and run it with `sudo`:

```bash
sudo APP_USER=litellm bash bootstrap-ubuntu.sh
```

What it does:

- installs UFW and enables it with a default deny-all incoming policy
- explicitly allows only `OpenSSH` on the public interface — everything else is blocked
- installs Docker Engine and Compose plugin from Docker’s apt repo
- adds the app user to the `docker` group
- creates `/home/litellm/litellm/config`

After it completes, log out and back in so group membership refreshes.

Install Tailscale on the VM and join it to your tailnet. Once Tailscale is up, allow the proxy listeners only on the Tailscale interface:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
sudo ufw allow in on tailscale0 to any port 4000 proto tcp
sudo ufw allow in on tailscale0 to any port 4001 proto tcp
```

If you later harden SSH further, keep this sequence:

1. confirm `ssh litellm@YOUR_SERVER_IP` works with your key
2. confirm `sudo -i` works
3. then disable password auth and direct root SSH login

Do not disable root SSH login before those checks pass.

Recommended final SSH settings in `/etc/ssh/sshd_config`:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

Then reload SSH:

```bash
sudo systemctl reload ssh
```

## 4. Prepare deployment files

On the server, create the working directory:

```bash
mkdir -p ~/litellm
cd ~/litellm
mkdir -p config
```

Copy these templates from this repo:

- `deploy/litellm/.env.example` to `~/litellm/.env`
- `deploy/litellm/docker-compose.yml` to `~/litellm/docker-compose.yml`
- `deploy/litellm/config/litellm_config.yaml` to `~/litellm/config/litellm_config.yaml`
- `deploy/caddy/Caddyfile` to `~/litellm/Caddyfile`

Generate secrets with:

```bash
bash scripts/generate-secrets.sh
```

Then fill in `~/litellm/.env`:

```dotenv
DATABASE_URL=postgresql://USER:PASSWORD@HOST/DBNAME?sslmode=require&channel_binding=require
LITELLM_MASTER_KEY=REPLACE_ME
LITELLM_SALT_KEY=REPLACE_ME
LITELLM_IMAGE_TAG=v1.83.10-stable
STORE_MODEL_IN_DB=True
TS_BIND_IP=REPLACE_WITH_TAILSCALE_IP
UI_USERNAME=REPLACE_ME
UI_PASSWORD=REPLACE_ME
```

Rules:

- `LITELLM_MASTER_KEY` and `LITELLM_SALT_KEY` must be strong random secrets.
- Do not rotate `LITELLM_SALT_KEY` casually after data is stored; DB-encrypted values depend on it.
- This repo currently pins `LITELLM_IMAGE_TAG=v1.83.10-stable`. LiteLLM releases new versions very quickly, particularly in response to any security issues. Change the version deliberately when you choose to upgrade.
- `STORE_MODEL_IN_DB=True` must be present if you want to save models through the LiteLLM UI/API without baking them into config files.
- `TS_BIND_IP` must be the VM's Tailscale IPv4 so Docker publishes only on the private interface.
- `UI_USERNAME` and `UI_PASSWORD` enable LiteLLM's built-in UI login prompt.
- paste secret values directly after `=`
- use double quotes around the value if it contains spaces, `#`, quotes, or other special characters that could be parsed awkwardly in a `.env` file
- do not include extra spaces, trailing whitespace, or line breaks inside the secret values

## 5. Start the stack

From `~/litellm` on the server:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Watch logs if needed:

```bash
docker compose logs -f litellm
docker compose logs -f caddy
```

Network posture after this:

- UFW denies all incoming traffic from the public internet except SSH on port 22
- SSH on port 22 is only possible with a private key
- `4000` and `4001` are bound to the Tailscale IP only — they are not on the public interface at all
- `4000` is the agent listener and allows only `/v1/*` and `/health`
- `4001` is the admin listener for the full LiteLLM app
- We aren't trying to hide `4001` from attackers, we're just making it different enough that our agents are less likely to do something we don't want, and so that we can add further security rules if we want (like further auth on `4001`)
- LiteLLM itself is reachable only inside Docker networking
- LiteLLM is not intended to be reachable from the public internet

## 6. Access LiteLLM safely

Find the VM’s Tailscale name or IP:

```bash
tailscale status
tailscale ip -4
```

Then access LiteLLM over Tailscale, for example:

```text
http://litellm.your-tailnet.ts.net:4000
http://100.x.y.z:4000
```

The admin UI will be:

```text
http://litellm.your-tailnet.ts.net:4001/ui/
http://100.x.y.z:4001/ui/
```

Expected behavior:

- `:4000` is for agents and API clients; only `/v1/*` and `/health` are reachable
- `:4000/ui` should not work
- `:4001` is for admins
- `:4001/ui` may redirect to `:4001/ui/`
- `:4001/ui/` should prompt for `UI_USERNAME` / `UI_PASSWORD`

If you want an extra admin-only path, you can still use an SSH tunnel:

```bash
ssh -L 4001:YOUR_TAILSCALE_IP:4001 litellm@YOUR_SERVER_IP
```

Then open:

```text
http://127.0.0.1:4001/ui/
```

That is optional in the Tailscale architecture, not required.

## 7. Configure LiteLLM

Inside the LiteLLM UI:

1. Confirm DB-backed operation is working.
2. Add provider credentials.
3. Add model aliases.
4. Create one virtual key per agent or integration.
5. Apply budgets, allowlists, and optional rate limits to each key.

Suggested conventions:

- alias user-facing models with stable names such as `gpt-5`, `gpt-5-mini`, `claude-sonnet`, `gemini-pro`
- keep provider-specific model IDs behind those aliases
- use one virtual key per agent, not one shared key for everything

## 8. Give access to a new agent

For most new users or agents, the process is:

1. Create a LiteLLM virtual key in the UI.
2. Restrict it to the models that agent should access.
3. Set a budget and optional rate limit.
4. Hand over only:
   - base URL: `http://litellm.your-tailnet.ts.net:4000`
   - API key: the LiteLLM virtual key
   - allowed model alias names

That is the normal onboarding path. No redeploy should be needed.

## 9. Validation checklist

Run these checks before treating the service as production-ready:

- `curl http://litellm.your-tailnet.ts.net:4000/health` or the current LiteLLM health endpoint you have validated for your release
- a real completion request over Tailscale
- confirm `4000` and `4001` are not reachable from the public internet
- confirm `http://litellm.your-tailnet.ts.net:4000/ui` is blocked
- confirm `http://litellm.your-tailnet.ts.net:4001/ui` redirects to `/ui/` or loads directly
- confirm the UI works over `http://litellm.your-tailnet.ts.net:4001/ui/`
- confirm the UI prompts for `UI_USERNAME` / `UI_PASSWORD`
- confirm a virtual key can call only the intended model aliases
- confirm spend/budget tracking appears in LiteLLM

Resource checks on the VM:

```bash
docker stats
free -h
df -h
```

## 10. Ongoing operations

Normal operations should be:

1. Add or update provider credentials in LiteLLM
2. Add or change model aliases in LiteLLM
3. Issue, rotate, or revoke virtual keys
4. Monitor spend and error rates
5. Upgrade LiteLLM by changing the pinned image tag deliberately

Avoid normalizing direct edits to provider keys in `.env`. That defeats the control-plane design.

## 11. Troubleshooting

### LiteLLM container starts then exits with DB connection errors

If logs show connection failures such as:

```text
httpx.ConnectError: All connection attempts failed
ERROR:    Application startup failed. Exiting.
```

check `DATABASE_URL` first.

Common causes:

- typo in the URL
- accidental truncation when pasting into `.env`
- trailing whitespace or line breaks
- password characters copied incorrectly

Checks:

```bash
cd ~/litellm
grep '^DATABASE_URL=' .env
docker compose logs --tail=100 litellm
```

The value should be one complete line copied exactly from Neon.

### LiteLLM UI says `Set 'STORE_MODEL_IN_DB=True'`

If the dashboard test works but saving the model fails with:

```text
Set 'STORE_MODEL_IN_DB=True' in your env to enable this feature.
```

add this line to `~/litellm/.env`:

```dotenv
STORE_MODEL_IN_DB=True
```

Then restart LiteLLM:

```bash
cd ~/litellm
docker compose down
docker compose up -d
```

Even if `store_model_in_db: true` is already present in `litellm_config.yaml`, some LiteLLM builds still enforce the env flag for UI-backed model creation.

### LiteLLM hangs on `Running prisma migrate deploy`

If logs show repeated messages like:

```text
Running prisma migrate deploy
Attempt 1 timed out
Attempt 2 timed out
```

the most likely cause is that `DATABASE_URL` is using Neon’s pooled connection string instead of the direct one.

Fix:

1. Go to Neon.
2. Copy the direct PostgreSQL connection string.
3. Replace `DATABASE_URL` in `~/litellm/.env`.
4. Restart LiteLLM:

```bash
cd ~/litellm
docker compose down
docker compose up
```

Quick rule:

- host contains `-pooler`: wrong for this setup
- direct host without `-pooler`: use this

### LiteLLM is up but Tailscale access to `:4000` or `:4001` fails

If the Tailscale hostname resolves but the browser shows `connection refused`, try running the following commands on the VM:

```bash
cd ~/litellm
docker compose ps
docker compose logs --tail=100 litellm
docker compose logs --tail=100 caddy
sudo ufw status
ss -ltnp | grep 400
tailscale ip -4
curl http://127.0.0.1:4000
```

Interpretation:

- container not running: inspect LiteLLM logs
- nothing listening on `:4000`: LiteLLM failed to start
- LiteLLM works on `127.0.0.1:4000` but not on the Tailscale hostname: check `TS_BIND_IP`, Caddy logs, and the `tailscale0` UFW rules

### UI is visible on `:4000`

The agent listener allowlists only `/v1/*` and `/health` — everything else should return 404. If `http://YOUR_TAILSCALE_IP:4000/ui` still loads:

1. confirm Caddy is running
2. confirm the current `Caddyfile` was copied to the server
3. restart the stack

```bash
cd ~/litellm
docker compose down
docker compose up -d
```

### Validate the Caddy listener config

The Caddyfile should use bare listener addresses with an allowlist on `:4000`:

```caddy
:4000 {
    encode zstd gzip

    @allowed path /v1/* /health /health/*

    handle @allowed {
        reverse_proxy litellm:4000
    }

    respond 404
}

:4001 {
    encode zstd gzip
    reverse_proxy litellm:4000
}
```

If the live file differs from the template, replace it and restart Caddy:

```bash
cd ~/litellm
docker compose restart caddy
```

### UI does not prompt for login

LiteLLM's UI auth depends on environment variables. Check:

```bash
cd ~/litellm
grep '^UI_' .env
docker compose restart litellm caddy
```

If `UI_USERNAME` and `UI_PASSWORD` are not set, add them and restart the stack.

## 12. Backups

Back up:

- `~/litellm/.env`
- `~/litellm/docker-compose.yml`
- `~/litellm/config/litellm_config.yaml`
- `~/litellm/Caddyfile`
- Neon project and credential details

Also document:

- the Tailscale hostname or IP used for the gateway
- who can access the tailnet / admin path
- the current pinned LiteLLM image tag
- which SSH admin keys are authorized on the server

## Design notes

**Why Tailscale instead of a public URL with HTTPS?**
Tailscale is the access gate: only authorized tailnet members can reach the gateway at all. This avoids exposing LiteLLM to the public internet entirely, which is a stronger default than HTTPS + IP allowlist on a public port.

**Why an allowlist on `:4000` if Tailscale already controls access?**
Tailscale controls who reaches the gateway. The allowlist on the agent port constrains what a tailnet member holding a virtual key can do. An agent with a stolen or compromised key can only call completions — it cannot reach key management, model management, spend logs, or config endpoints even from inside the tailnet. Port `:4001` is unrestricted and should only be given to admins.

**Why not restrict `:4001` further?**
Port `:4001` already has two auth layers: Tailscale network access and LiteLLM's own credentials (`UI_USERNAME`/`UI_PASSWORD` for the UI, master key for the API). If your tailnet has mixed trust levels — agents are also tailnet members — consider using Tailscale ACLs to restrict which nodes can reach port `:4001` on the VM.

**Why is the LiteLLM config minimal?**
Config key names in LiteLLM can change between releases. The template only sets keys with stable, documented behaviour. Log retention and other optional settings should be validated against the release you are running before adding them. Prompt-level log retention will likely increase your database hosting cost.
