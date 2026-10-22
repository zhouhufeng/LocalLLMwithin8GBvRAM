# Local LLM within 8 GB of VRAM

Running a capable local LLM on an **old GTX 1080 (8 GB, Pascal, 2016)**: two setups that work, with measured numbers.

| | **Method 1: Bonsai 2 27B (1.75-bit)** | **Method 2: Ollama 9B (Q4_K_M)** |
|---|---|---|
| Model | `prism-ml/Ternary-Bonsai-2-27B-gguf`, file `PTQ1_0` (Prism ML's compression of Qwen 3.8 27B) | `richardyoung/qwythos-9b-abliterated` (qwen35 arch, 9B) |
| File size | 5.95 GB | 5.6 GB |
| Engine | Prism ML's llama.cpp fork, **rebuilt from source for sm_61** | Stock Ollama |
| VRAM used | 6.6–7.2 GB (context 8k) | 5.5 GB (context 8k) |
| Generation speed | **~20 tok/s** short tests, **~16 tok/s** in a long real chat | **~35 tok/s** |
| Prompt reading | ~85 tok/s | ~260 tok/s |
| Short Q&A, end to end | 5–10 s (thinking on) | ~4 s (thinking on) |
| Setup effort | High: ~10 min compile + workaround | One command |
| Best for | Smartest answers that fit on the card | Speed, convenience, longer prompts |

**Verdict from real use: both give good answers at a comfortable speed.** In a longer real conversation in the web UI, the 27B gave high-quality answers at about **16 tok/s**, which is still faster than reading speed. Pick Method 1 for the bigger, smarter model, or Method 2 for the quickest setup.

Both run 100% on the GPU, both expose an OpenAI-compatible API and support tool calling and thinking mode.

- **[Method 1: Bonsai 2 27B with llama.cpp →](docs/method1-bonsai-27b-llamacpp.md)**
- **[Method 2: Ollama 9B →](docs/method2-ollama-9b.md)**

## Test machine

| Part | Spec |
|---|---|
| GPU | NVIDIA GeForce GTX 1080, 8 GB (Pascal, compute capability 6.1) |
| Driver | 545.29.06 (supports CUDA ≤ 12.3) |
| CUDA toolkit | 12.0 (`nvcc` V12.0.140) |
| CPU / RAM | Intel i7-6700 / 16 GB |
| OS | Ubuntu, Linux 6.5 |

## The key lessons

1. **A 27B model fits in 8 GB if it's compressed hard enough.** Prism ML's ternary Bonsai 2 27B is 5.95 GB at ~1.75 bits/weight, leaving ~1.5 GB for the KV cache and compute buffers. That's enough for an 8k context.
2. **Ollama cannot load the Bonsai file.** `PTQ1_0` is a custom quant type that only Prism ML's llama.cpp fork understands.
3. **The prebuilt CUDA binary crashes on an older driver.** It ships Pascal code only as PTX compiled with CUDA 12.4. A 545 driver (CUDA 12.3) can't JIT it:
   `CUDA error: the provided PTX was compiled with an unsupported toolchain.`
   **Fix:** build the fork yourself for `sm_61` with your local CUDA toolkit ([scripts/build_llamacpp_sm61.sh](scripts/build_llamacpp_sm61.sh)). You don't need a driver upgrade.
4. **Cap the context.** Without `BONSAI_CTX=8192 -np 1`, the start script sizes the context from system RAM and runs out of VRAM.
5. **Free the GPU first.** Only one model fits at a time. An idle Ollama model keeps holding VRAM for 5 minutes (`ollama stop <model>`).
6. **Thinking mode is the main source of latency.** A haiku took 41 s on the 27B because it "thought" for 800 tokens. Turn reasoning off/low for chatty use.

## Can it power Claude Code / coding agents?

The llama.cpp server also speaks the Anthropic `/v1/messages` API, and a tool-call test worked. **But it isn't practical on this card.** A coding agent's system prompt and tool definitions alone are ~15–25k tokens, more than the 8k context that fits. At ~85 tok/s prompt reading, the first turn would also take minutes. Use these setups for chat, Q&A, summarizing and light tool use.

## Repo layout

```
README.md                          this overview
docs/method1-bonsai-27b-llamacpp.md   step-by-step for the 27B route (with troubleshooting)
docs/method2-ollama-9b.md             step-by-step for the Ollama route
scripts/build_llamacpp_sm61.sh     build Prism ML's llama.cpp fork for GTX 10xx
scripts/start_bonsai27b.sh         start the 27B chat server with 8 GB-safe settings
scripts/bench_chat.sh              measure tok/s on any OpenAI-compatible endpoint
```

The work was done interactively with Claude Code on 2026-10-20/21; the docs are distilled from those sessions.
