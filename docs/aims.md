# Aims

## Primary aims

This repo exists to document and support a LiteLLM gateway deployment with these properties:

1. Safe by default
2. Dynamically manageable without code pushes for routine model changes
3. Cost-controlled at the gateway layer
4. Operationally sensible for a small, cloud-hosted setup

## What “good” looks like

- Agents never receive raw provider credentials such as `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`.
- LiteLLM is reachable only on the private tailnet, not on the public internet.
- LiteLLM is not exposed on a public port.
- Model aliases, provider credentials, and virtual keys are managed through LiteLLM’s DB-backed control plane.
- New agent access usually means issuing or rotating a LiteLLM virtual key, not changing application code.
- Spend can be constrained with budgets, model allowlists, and rate limits per key.
- Operational secrets are few and explicit:
  - `DATABASE_URL`
  - `LITELLM_MASTER_KEY`
  - `LITELLM_SALT_KEY`
- The database is separate from the VM running the gateway.

## Architecture intent

The intended baseline architecture is:

- Hetzner Cloud VM for the gateway runtime
- Neon PostgreSQL for persistent control-plane state
- Docker Compose for repeatable deployment
- Tailscale for private network access to the gateway
- LiteLLM itself not published directly on the host
- agent listener exposed only to the tailnet on port `4000`
- admin listener exposed only to the tailnet on port `4001`
- LiteLLM UI kept off the public internet; use the admin listener and optionally SSH tunnel for admin access

## Non-goals

- Exposing provider keys directly to agents
- Requiring redeploys for everyday model additions and alias changes
- Treating the VM as a pet server with undocumented manual state
- Publicly exposing the admin UI without an additional control layer

## Operating principles

- Prefer pinned versions over floating tags for production.
- Prefer private-by-default access for administration.
- Prefer templates and scripts over one-off shell history.
- Keep the docs usable by two audiences:
  - someone doing the first full deployment
  - someone who only needs a new agent key
