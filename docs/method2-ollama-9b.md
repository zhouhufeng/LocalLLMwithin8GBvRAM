# Method 2: Ollama with a 9B model (the easy route)

If you want a capable local model working in a few minutes, a ~9B model at 4-bit in stock **Ollama** fits an 8 GB card with room to spare and runs faster than the 27B route.

Model used: [`richardyoung/qwythos-9b-abliterated`](https://ollama.com/richardyoung/qwythos-9b-abliterated)

| Property | Value (from `ollama show`) |
|---|---|
| Architecture | qwen35 |
| Parameters | 9.0B |
| Quantization | Q4_K_M |
| Download size | 5.6 GB |
| Capabilities | tools, thinking, completion |
| Default `num_ctx` | 8192 |

> "Abliterated" means a community fine-tune with the refusal behaviour removed. It will answer things a stock model declines, so use it responsibly. Any Qwen-family 7–9B Q4 model from the Ollama library works the same way if you'd prefer a stock one.

## Setup

```bash
curl -fsSL https://ollama.com/install.sh | sh        # if Ollama isn't installed
ollama pull richardyoung/qwythos-9b-abliterated
ollama run  richardyoung/qwythos-9b-abliterated       # chat in the terminal
```

API (OpenAI-compatible): `http://localhost:11434/v1`. Native: `http://localhost:11434/api/chat`.
For a browser UI, point [Open WebUI](https://github.com/open-webui/open-webui) at `http://localhost:11434`.

## Measured performance (GTX 1080)

`ollama ps` shows **100% GPU**, 5.5 GB VRAM, 8192 context.

| Test | Prompt | Generation | Total |
|---|---|---|---|
| "What are you good at?" (first call, includes 19.7 s model load) | 22 tok, 0.3 s | 197 tok @ 34.7 tok/s | 25.7 s |
| Sheep riddle → "9" (correct) | 33 tok, 0.3 s | 128 tok @ 34.9 tok/s | 4.1 s |
| 1,560-token prompt, thinking off | 5.9 s (**262 tok/s**) | 34.9 tok/s | ~7 s |

Compared with the 27B route, it generates **~1.7× faster** and reads prompts **~3× faster**. You trade some answer quality for that (9B vs 27B parameters).

## Tips

- **Free VRAM before switching methods.** Ollama keeps a model loaded for 5 minutes after the last request: `ollama stop richardyoung/qwythos-9b-abliterated`.
- **Turn thinking off** for faster replies: `/set nothink` in `ollama run`, or `"think": false` in `/api/chat`.
- **More context:** `/set parameter num_ctx 16384` should still fit, since 9B Q4 leaves ~2.5 GB free. I haven't measured it.
