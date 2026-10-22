# Method 1: Bonsai 2 27B (Qwen 3.8 27B, 1.75-bit) on a GTX 1080

Prism ML compressed Qwen 3.8 27B into **Ternary Bonsai 2 27B**. The `PTQ1_0` GGUF is **5.95 GB**, small enough to sit entirely in 8 GB of VRAM.

Result on the GTX 1080: **~20 tokens/s**, correct answers on reasoning checks, browser chat at `http://localhost:8080`.

## 1. Get the demo repo and model

```bash
git clone https://github.com/PrismML-Eng/Bonsai-demo.git
cd Bonsai-demo
mkdir -p models/bonsai2-gguf/27B
# Direct curl is more reliable than an old huggingface-cli (mine stalled at 0 bytes). -C - resumes.
curl -L --fail -C - -o models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf \
  https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf
sha256sum models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PTQ1_0.gguf
# expect 53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3
```

Other files in that HF repo: `PQ2_0` (7.2 GB, too big for 8 GB with any context) and `F16` (54 GB).

## 2. Try the prebuilt binary (it may fail on older drivers)

```bash
./scripts/download_binaries.sh      # or ./setup.sh
BONSAI_CTX=8192 ./scripts/start_llama_server.sh -np 1
```

With driver 545 (CUDA 12.3) this crashes at model load:

```
CUDA error: the provided PTX was compiled with an unsupported toolchain.
```

**Why:** the prebuilt has no native `sm_61` (Pascal) code, only PTX produced by CUDA 12.4. The driver must JIT-compile that PTX, and a 12.3 driver refuses 12.4 PTX.
**Fix options:** upgrade the NVIDIA driver to one that supports CUDA ≥ 12.4, **or** build from source (next step). I built from source.

## 3. Build Prism ML's llama.cpp fork for sm_61

Requirements: CUDA toolkit (`nvcc`, 12.0 worked), gcc/g++, and cmake + ninja. If cmake/ninja aren't installed, the script puts them in a throwaway Python venv, so nothing is installed system-wide.

```bash
/path/to/this-repo/scripts/build_llamacpp_sm61.sh /path/to/Bonsai-demo
```

That script:
- Clones `llama.cpp` into the demo if missing. Use the commit the demo pins: `setup.sh` fetches it. My build used commit `73bfe6cc4`, build 10787.
- Configures with `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61`.
- Builds only `llama-server` (515 steps, **~10 min** on an i7-6700 with `-j 6`).
- Backs up `bin/cuda` to `bin/cuda.prebuilt-backup` and installs the new build there.

Notes:
- An earlier build attempt stopped at step 94/525. Building just the `llama-server` target with fewer jobs went through cleanly. If it dies, lower `JOBS` (RAM pressure).
- CUDA 12.0 officially supports gcc ≤ 12. If nvcc complains about your gcc, set `CUDA_HOST_CXX=g++-12`.
- **`setup.sh` / `download_binaries.sh` delete `bin/cuda` and restore the prebuilt.** Re-run the build script afterwards.

## 4. Start the chat server with 8 GB-safe settings

```bash
/path/to/this-repo/scripts/start_bonsai27b.sh /path/to/Bonsai-demo
# = BONSAI_CTX=8192 ./scripts/start_llama_server.sh -np 1
```

- `-ngl 99`: all layers on the GPU (the script auto-detects this).
- `BONSAI_CTX=8192`: 8k context. Larger runs out of VRAM.
- `-np 1`: one chat slot, so the KV cache isn't split or duplicated.
- Sampling the demo uses: `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --jinja`.

Open **http://localhost:8080**. The API is at `http://localhost:8080/v1` (OpenAI) and `/v1/messages` (Anthropic).

VRAM after load: **6.6 GB** idle, **~7.2 GB** after chatting (of 8 GB).

## 5. Measured performance (GTX 1080)

| Test | Prompt | Generation | Total |
|---|---|---|---|
| "What are you good at?" | 64 tok, 2.8 s | 108 tok @ 20.9 tok/s | 8.0 s |
| Sheep riddle → "9" (correct) | 33 tok, 1.4 s | 66 tok @ 20.9 tok/s | 4.5 s |
| Haiku (thought ~800 tokens) | 19 tok, 1.3 s | 801 tok @ 19.9 tok/s | 41.5 s |
| 1,560-token prompt, thinking off | 18.4 s (**85 tok/s**) | 13.6 tok/s | ~20 s |

**Real use:** in a longer chat in the web UI, it gave good, detailed answers at about **16 tok/s**. Speed drops a little as the conversation fills the context, but it's still faster than reading speed.

Takeaways:
- Generation at 16–20 tok/s reads comfortably.
- **Thinking adds most of the waiting.** In the web UI, use the lightbulb button to set reasoning to Off/Low. Over the API, pass `"chat_template_kwargs": {"enable_thinking": false}`.
- **Long pasted text is slow to ingest** (~20 s per page). Follow-ups in the same chat reuse the cache and are fast.
- Text only. The vision projector (mmproj, +0.63 GB) doesn't leave room for context on 8 GB.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `PTX was compiled with an unsupported toolchain` | Driver older than the binary's CUDA. Build for sm_61 (step 3) or update the driver. |
| CUDA out of memory at load | Another process holds VRAM (often Ollama: `ollama ps`, `ollama stop <model>`), or the context is too large. |
| Download stuck at 0 bytes | Old `huggingface_hub`. Use the `curl -C -` command above. |
| Rebuilt binary disappeared | `setup.sh`/`download_binaries.sh` restored the prebuilt. Rebuild. |
