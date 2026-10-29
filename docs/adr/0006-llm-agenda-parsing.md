# ADR 0006: Parse pasted agendas with Claude on Bedrock, outside the VPC

- Status: accepted
- Date: 2026-10-22

## Context

Agendas arrive as emails, chat messages and notes, not as forms. We want a **Paste an agenda**
feature: the user pastes text, an LLM turns it into a structured agenda, the app shows a pre-filled
form, and the user checks it and saves it. The model suggests; the person decides.

Constraints:
- **No NAT.** The API Lambda runs in the VPC to reach Aurora and has no internet access. A NAT gateway
  (~$33/month) or an interface endpoint (~$7.30/month per AZ) would break "$0 when idle" (Lab 4).
- **Cost.** Every parse is billed per token, so the endpoint must be authenticated and limited.
- **Text from outside.** Pasted emails can contain instructions ("ignore your instructions…"). The
  model's output is untrusted until it has been validated and confirmed by the user.

## Decision

- **Model:** Claude Opus 5.5 on Amazon Bedrock (`anthropic.claude-opus-5-5`, effort `low`; until this account gets 5.x access it runs on Opus 4.6, `us.anthropic.claude-opus-4-6-v1`, see docs/lab6-agenda-parser.md), called
  through the Anthropic Messages API (`AnthropicBedrockMantle`). The model ID is configuration
  (`PARSER_MODEL`), so Haiku 5.5 can be swapped in without a code change.
- **The parser runs outside the VPC** as its own Lambda (`agenda-parser`, same backend image, other
  handler) behind a function URL. It needs no database: text in, JSON out. Outside the VPC it reaches
  Bedrock and Cognito's JWKS over the internet with no NAT and no endpoint, and costs nothing idle.
- **The model never writes.** It answers through one tool, `record_agenda`, whose input schema is the
  `ParsedAgenda` Pydantic model. The output is validated (one retry with the validation error, then
  422). Saving goes through the existing API (`PUT /api/v1/meetings/{id}/agenda`) with its usual
  validation and ownership checks. The API stores the model's suggestion (`ai_suggestion`, with model
  and prompt version) next to what the user saved.
- **Guard rails on the endpoint:** a valid Cognito access token is required (401 otherwise), text over
  10,000 characters is rejected (413) before the model is called, and a $5/month AWS Budgets alarm
  emails the owner.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Call Bedrock from the API through a VPC interface endpoint | ~$7.30/month per AZ (~$15 for two) whether or not anyone parses, for a feature that does not need the database. It also puts the LLM call on the same function as every write. |
| The Claude API directly (api.anthropic.com) instead of Bedrock | A long-lived API key to store and rotate, a second bill outside AWS Budgets, and no IAM, CloudTrail or VPC-endpoint options. Bedrock lets the Lambda role call the model with no secret at all. |
| A regular-expression parser | Free and predictable, but agendas come in any language and layout ("Пн 10:00 … 45 хв", "next Tuesday after lunch"). Every new format would need a new rule, and relative dates need a calendar anyway. |

## Consequences

- **Cost per parse:** about $0.01–0.02 with Opus 5.5 for a short agenda (~1,500–2,500 input and
  ~300–600 output tokens); about 40× less with Haiku 5.5. Measured values are in the test table.
- **What is logged:** one JSON line per parse in `/aws/lambda/<project>-agenda-parser`: user (sub),
  model, prompt version, input and output tokens, latency and cost in dollars. The pasted text itself
  is not logged.
- **Quality signal for free:** `meetings.ai_suggestion` vs `meetings.agenda` shows every correction the
  user made, per prompt version.
- **When Bedrock is down or throttling:** the parser answers 429/503, the screen says "the AI service is
  busy" and offers *Type it in instead*. Everything else in Spry keeps working, because nothing else
  depends on the parser.
- **Open risks:** the role allows `bedrock-mantle:CreateInference` on `*` (to be narrowed to one model
  and region); someone with many accounts could still spend money (per-user rate limits would be next).
