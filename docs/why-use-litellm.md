# Why Use LiteLLM

This setup is not just about putting a proxy in front of model APIs. The point is to move model access, routing, cost controls, and operational policy into one shared layer instead of re-solving them inside every repo.

## Core reasons

### Avoid vendor lock-in

If each repo talks directly to one provider, that repo quietly becomes coupled to that provider’s auth model, model IDs, feature quirks, and rollout schedule.

With LiteLLM in the middle:

- apps target one OpenAI-compatible interface
- provider-specific credentials stay in the gateway
- model aliases can stay stable even when the underlying provider changes
- moving a workload from one vendor to another is mostly a gateway change, not a repo-wide migration

That does not eliminate all provider differences, but it reduces how much of that difference leaks into product code.

### Change models and routing without pushing code

If model choice lives inside application code, normal operational changes turn into deploy work:

- trying a new model
- shifting a team from one alias to another
- testing fallback behavior
- tightening a model allowlist
- adjusting spend controls for one agent

With LiteLLM, a lot of that can move into the gateway control plane instead:

- update aliases
- add or remove models
- rotate virtual keys
- change budgets and limits
- test routing and fallback rules

That is useful because model operations change faster than most repos should need to redeploy.

### Faster adoption of new models

A practical advantage of using a gateway layer is speed. When a new model appears, you often want to expose it immediately for evaluation without waiting for every consuming repo to add bespoke support.

In practice, that means new releases can show up in the LiteLLM interface quickly. The working pattern here is: provider support lands, the gateway can expose the model, and internal users can test through the shared endpoint instead of waiting on multiple code changes. The point is not one specific release; the point is shortening the path from “new model exists” to “the team can evaluate it”.

### Budget management and usage tracking

Direct provider keys spread spend across repos and teams in a way that is hard to govern.

LiteLLM gives a better operating point:

- virtual keys per agent or integration
- per-key budgets
- model allowlists
- optional rate limits
- centralized spend metadata and logs

That makes it easier to answer operational questions such as:

- which agent is responsible for the spend
- which team should get access to which models
- where usage jumped unexpectedly
- which key should be revoked without breaking everything else

### Separate guardrails and routing from individual repos

This is one of the most important architectural reasons.

If every repo implements its own model selection, fallback logic, provider switching, access policy, and safety checks, you get:

- duplicated infrastructure logic
- inconsistent controls between projects
- more secrets in more places
- slower rollout of policy changes

Moving that layer into LiteLLM lets repos stay focused on product logic while the shared gateway handles:

- routing
- fallback and model indirection
- key management
- access policy
- spend controls
- common guardrail decisions

That separation is especially valuable when many small agents or internal tools need model access but should not each become their own infrastructure project.

## Why this matters for this repo specifically

This repo is built around a simple operating model:

- apps and agents get a LiteLLM virtual key, not raw provider credentials
- the gateway is reachable only over Tailscale
- the database-backed control plane stores models, keys, and spend metadata
- routine model management should happen in LiteLLM, not through code pushes

That leads to a cleaner division of responsibility:

- repos own prompts, workflows, and product behavior
- the gateway owns provider credentials, routing, access policy, and spend controls

## Good fit

LiteLLM is a strong fit when you have:

- multiple repos or agents that need model access
- more than one provider in play now or soon
- a need for per-agent budgets and revocable keys
- a desire to test models quickly without repeated app changes
- an operational preference for centralizing secrets and policy

## Tradeoff to accept

You are adding one more layer to operate. That means:

- another service to monitor
- another config surface to manage
- another dependency in the request path

For a single experimental script, that may not be worth it. For a growing set of agents, tools, and repos, it usually is.
