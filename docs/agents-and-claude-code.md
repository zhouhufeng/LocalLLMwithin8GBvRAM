# Using Bonsai 2 27B to power local agents and Claude Code

This guide builds on [Method 1](method1-bonsai-27b-llamacpp.md). It assumes the 27B server already runs on the GTX 1080.

> **Status:** One part is verified on the GTX 1080: the Anthropic `/v1/messages` endpoint returned a correct tool call. The 32k 4-bit-cache setup, Claude Code, aider and Hermes steps below are **not yet tested on this card**. Their memory and timing figures are estimates from the measured speeds and the demo's `KV-CACHE.md`. I'll update this page with real numbers.

## The one constraint: context length

Agents send large prompts. Claude Code's instructions and tool definitions alone are roughly **15–25k tokens** (estimate), before any of your code. The default 8 GB setup only has **8k** context, so the request fails with "prompt too long".

The fix is the fork's **4-bit KV cache** (`BONSAI_KV4=1`, see the demo's `KV-CACHE.md`). On the 27B it stores about 18 KiB per token instead of 64 KiB:

| Context | FP16 KV cache | 4-bit KV cache | Fits in 8 GB? (estimate) |
|---|---|---|---|
| 8k | 0.5 GB | 0.14 GB | yes (measured: 6.6–7.2 GB total) |
| 32k | 2.0 GB | ~0.56 GB | **yes with 4-bit** |
| 48k | 3.0 GB | ~0.84 GB | probably, with 4-bit |
| 64k | 4.0 GB | ~1.1 GB | tight / unlikely |

## Step 1: Free the GPU

Only one model fits in 8 GB at a time.

```bash
ollama ps                    # anything listed holds VRAM
ollama stop <model-name>
nvidia-smi                   # should show only a few hundred MiB in use
```

## Step 2: Start the server with a 32k context

From the `Bonsai-demo` folder:

```bash
BONSAI_KV4=1 BONSAI_CTX=32768 ./scripts/start_llama_server.sh -np 1
```

This adds `--cache-type-k q4_0 --cache-type-v q4_0` (flash attention is already on). If it runs out of memory, try `BONSAI_CTX=24576`.

**Optional quality boost:** a KV calibration file. It needs the `llama-kv-mean-center` tool, so build it once alongside the server, then make the bias file:

```bash
TARGETS="llama-server llama-kv-mean-center" /path/to/LocalLLMwithin8GBvRAM/scripts/build_llamacpp_sm61.sh .
./scripts/make_kv_bias.sh            # writes <model>-kv-bias.gguf next to the model; used automatically
```

Without the bias file the 4-bit cache still works, with slightly lower quality.

Endpoints:
- OpenAI style: `http://127.0.0.1:8080/v1` (aider, Hermes, Open WebUI, OpenHands, Continue, …)
- Anthropic style: `http://127.0.0.1:8080/v1/messages` (Claude Code)

Quick tool-call check (this one is verified):

```bash
curl -s http://127.0.0.1:8080/v1/messages -H 'Content-Type: application/json' \
  -H 'x-api-key: none' -H 'anthropic-version: 2023-06-01' -d '{
  "model":"bonsai","max_tokens":600,
  "messages":[{"role":"user","content":"What is 2+2? Use the tool."}],
  "tools":[{"name":"calc","description":"Evaluate arithmetic",
            "input_schema":{"type":"object","properties":{"expr":{"type":"string"}},"required":["expr"]}}]}'
# → "stop_reason": "tool_use", input {"expr": "2+2"}
```

## Step 3a: Claude Code

In a **separate terminal**, so your normal Claude Code sessions are unaffected:

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:8080 \
ANTHROPIC_AUTH_TOKEN=local \
ANTHROPIC_MODEL=bonsai \
ANTHROPIC_SMALL_FAST_MODEL=bonsai \
claude
```

What to expect on a GTX 1080:
- **First turn: about 3–5 minutes** (estimate). The ~20k-token setup is read at about 85 tok/s.
- **Later turns are faster.** The prompt cache reuses what was already read, but each file the agent opens adds reading time.
- **Answers stream at about 16–20 tok/s** (measured in chat).
- **Quality:** fine for small, well-scoped tasks. Expect much weaker multi-step coding than Claude itself.
- **Context fills fast:** 32k minus ~20k of setup leaves about 10k for your work. Keep sessions short and use `/clear` often.

Verdict: a fun experiment, not a daily driver on this card.

## Step 3b: Lighter agents (better fit for 8 GB)

These send much smaller prompts, so they get going in seconds instead of minutes.

**aider** (pair-programming in a git repo):

```bash
pip install aider-chat
aider --openai-api-base http://127.0.0.1:8080/v1 --openai-api-key x --model openai/bonsai
```

**Hermes agent** ships with the demo (`AGENT-DEMO.md`). It runs shell commands on your machine without asking (`--yolo`), so use it in a workspace where that's OK.

```bash
./scripts/agent/install_hermes.sh        # once; needs git, uv, Node.js 24+
```

The demo's `start_agent_server.sh` asks for 128k context and the 7.2 GB `PQ2_0` model with vision, which doesn't fit on 8 GB. Keep the Step 2 server (PTQ1_0, 32k, 4-bit KV) running instead, and point Hermes at `http://127.0.0.1:8080/v1`. Its demo's first turn was also ~20k tokens, so expect a similar few-minute start.

**Open WebUI** (chat with tools, web search, documents): add an OpenAI connection to `http://127.0.0.1:8080/v1`. The built-in llama-server page at `http://localhost:8080` also supports MCP tool servers.

## Recommendation

| Use | Setup | Experience on GTX 1080 |
|---|---|---|
| Chat / Q&A | 8k, default cache | great: good answers at ~16–20 tok/s (verified) |
| Coding helper | 32k + 4-bit KV + **aider** | best agent fit (estimate) |
| Autonomous agent | 32k + 4-bit KV + Hermes | works, slow first turn (estimate) |
| Claude Code | 32k + 4-bit KV | possible, minutes per first turn, tight context (estimate) |

For comfortable agent use, a GPU with 12–16 GB would allow 64k+ context and much faster prompt reading. The same commands apply.
