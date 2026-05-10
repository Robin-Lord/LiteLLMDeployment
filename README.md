# LiteLLM Remote Server Instructions

This repo is the working setup guide for a cloud-hosted LiteLLM gateway that gives you a single control point for model access, routing, spend control, and operational visibility.

## How to think about this

If you've not used LiteLLM before: it's a proxy that sits between your code and AI providers. Your apps send requests to one place in one format, and LiteLLM routes them to whichever AI provider is appropriate — handling keys, budgets, and rate limits centrally so individual apps don't have to.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#0f172a', 'primaryColor': '#1e293b', 'primaryTextColor': '#f8fafc', 'primaryBorderColor': '#334155', 'lineColor': '#818cf8', 'edgeLabelBackground': '#1e1b4b', 'fontFamily': 'trebuchet ms, verdana, arial', 'fontSize': '16px'}}}%%
flowchart LR
    A1(["Agent A"])
    A2(["Agent B"])
    A3(["Script"])

    GW(["LiteLLM Gateway"])

    O(["OpenAI"])
    AN(["Anthropic"])
    GO(["Google"])

    A1 -->|one key| GW
    A2 -->|one key| GW
    A3 -->|one key| GW
    GW -->|routes| O
    GW -->|routes| AN
    GW -->|routes| GO

    classDef app fill:#1d4ed8,stroke:#93c5fd,stroke-width:2px,color:#ffffff,font-weight:bold
    classDef gw fill:#7c3aed,stroke:#c4b5fd,stroke-width:4px,color:#ffffff,font-weight:bold
    classDef provider fill:#065f46,stroke:#6ee7b7,stroke-width:2px,color:#ffffff,font-weight:bold

    class A1,A2,A3 app
    class GW gw
    class O,AN,GO provider
```

Your apps never hold real provider API keys — only a LiteLLM virtual key that you can revoke, cap, or restrict to specific models. The rest of this setup adds Tailscale and Caddy on top so the gateway itself is only reachable by authorised devices, not the open internet.

## Architecture at a glance

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'lineColor': '#64748b', 'clusterBkg': '#f8fafc', 'clusterBorder': '#cbd5e1', 'edgeLabelBackground': '#f1f5f9'}}}%%
flowchart LR
    subgraph Internet["Open Internet"]
        PUB["Public Internet"]
    end

    subgraph Clients["Tailscale Clients"]
        A1["Agent / App Repo A"]
        A2["Agent / App Repo B"]
        A3["Scripts / Internal Tools"]
        ADM["Admin Device"]
    end

    subgraph Tailnet["Private Access Layer"]
        TS["Tailscale Tailnet"]
    end

    subgraph Gateway["Hetzner VM"]
        FW["UFW + host exposure rules<br/>public: 22 only<br/>tailscale0: 4000 and 4001"]
        SSH["SSH<br/>:22 key auth for admin access"]
        A["Caddy agent listener<br/>:4000 allows /v1/* and /health only"]
        AD["Caddy admin listener<br/>:4001 forwards full LiteLLM app"]
        L["LiteLLM backend<br/>inside Docker network"]
        G["Routing, budgets, virtual keys,<br/>allowlists, rate limits, guardrail layer"]
    end

    subgraph State["Persistent Control Plane"]
        DB["Neon PostgreSQL<br/>models, keys, config, spend metadata<br/>IP allowlist to VM public IP"]
    end

    subgraph Providers["Underlying Model Providers"]
        O["OpenAI"]
        AN["Anthropic"]
        GO["Google / Gemini"]
        OT["Other providers"]
    end

    PUB --> SSH
    PUB -. blocks 4000/4001 .-> FW
    A1 --> TS
    A2 --> TS
    A3 --> TS
    ADM --> TS
    TS --> FW
    FW --> A
    FW --> AD
    ADM -. optional admin shell .-> SSH
    A --> L
    AD --> L
    L --> G
    G <--> DB
    G --> O
    G --> AN
    G --> GO
    G --> OT

    classDef internet fill:#fee2e2,stroke:#ef4444,stroke-width:2px,color:#7f1d1d
    classDef client fill:#dbeafe,stroke:#3b82f6,stroke-width:2px,color:#1e3a8a
    classDef infra fill:#ede9fe,stroke:#7c3aed,stroke-width:2px,color:#3b0764
    classDef db fill:#fef3c7,stroke:#f59e0b,stroke-width:2px,color:#78350f
    classDef provider fill:#d1fae5,stroke:#10b981,stroke-width:2px,color:#064e3b

    class PUB internet
    class A1,A2,A3,ADM client
    class TS,FW,SSH,A,AD,L,G infra
    class DB db
    class O,AN,GO,OT provider
```

The practical shape is: Tailscale is the only entry point, agents use `:4000`, admins use `:4001`, and LiteLLM itself is not published directly on the public host interface.

Tailscale controls who can reach the gateway at all. The agent listener on `:4000` adds a second constraint: it allowlists only `/v1/*` and `/health`, so a compromised agent or stolen virtual key cannot reach LiteLLM's management API (key generation, model management, spend logs, config changes) even from inside the tailnet. Port `:4001` forwards everything and is for admins only.

## Quickstart: get access for a new agent

If the server already exists and you just need to use it, you only need:

1. The gateway base URL on the tailnet, for example `http://litellm.your-tailnet.ts.net:4000`
2. A LiteLLM virtual key created for your agent
3. One allowed model alias, for example `gpt-5` or `claude-sonnet`

Use the gateway like any OpenAI-compatible endpoint:

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_LITELLM_VIRTUAL_KEY",
    base_url="http://litellm.your-tailnet.ts.net:4000",
)

response = client.chat.completions.create(
    model="MODEL_ALIAS",
    messages=[{"role": "user", "content": "Hello"}],
)

print(response.choices[0].message.content)
```

Do not use raw provider keys directly. Access should be through LiteLLM virtual keys so spend limits, revocation, and model allowlists remain centralized.

Recommended endpoints:

- agents: `http://litellm.your-tailnet.ts.net:4000`
- admins: `http://litellm.your-tailnet.ts.net:4001/ui/`

## Docs map

- [Aims](docs/aims.md)
- [Setup Guide](docs/setup.md)
- [Why Use LiteLLM](docs/why-use-litellm.md)
- [SSH Backups](docs/ssh-backups.md)

## Repo layout

- `deploy/litellm/`: templates to copy onto the VM
- `deploy/caddy/`: reverse-proxy template used for the default Tailscale-only architecture
- `scripts/`: helper scripts for bootstrap and secret generation

Start with [docs/setup.md](docs/setup.md) if you are building the environment from scratch.
