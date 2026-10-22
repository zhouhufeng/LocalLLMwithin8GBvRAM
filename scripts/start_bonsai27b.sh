#!/bin/bash
# Start Bonsai 2 27B (PTQ1_0) with settings that fit an 8 GB GPU, then chat at http://localhost:8080
# Usage: ./start_bonsai27b.sh /path/to/Bonsai-demo [extra llama-server args]
set -euo pipefail
DEMO="$(cd "${1:?usage: $0 /path/to/Bonsai-demo}" && pwd)"; shift

# Only one model fits in 8 GB: warn if Ollama is still holding one
if command -v ollama >/dev/null && ollama ps 2>/dev/null | tail -n +2 | grep -q .; then
    echo "Warning: Ollama has a model loaded (see 'ollama ps'); run 'ollama stop <model>' to free VRAM." >&2
fi

cd "$DEMO"
BONSAI_CTX="${BONSAI_CTX:-8192}" exec ./scripts/start_llama_server.sh -np 1 "$@"
