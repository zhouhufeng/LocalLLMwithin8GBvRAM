#!/bin/bash
# Quick speed check against an OpenAI-compatible endpoint (llama-server or Ollama).
# Usage: ./bench_chat.sh [base_url] [model]
#   llama.cpp: ./bench_chat.sh http://127.0.0.1:8080/v1
#   Ollama:    ./bench_chat.sh http://127.0.0.1:11434/v1 richardyoung/qwythos-9b-abliterated
set -euo pipefail
URL="${1:-http://127.0.0.1:8080/v1}"
MODEL="${2:-local}"

for prompt in "Hi! In two sentences, what are you good at?" \
              "A farmer has 17 sheep; all but 9 run away. How many are left? Answer briefly."; do
    body=$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"max_tokens":1500,"messages":[{"role":"user","content":sys.argv[2]}]}))' "$MODEL" "$prompt")
    start=$(date +%s.%N)
    resp=$(curl -s "$URL/chat/completions" -H 'Content-Type: application/json' -d "$body")
    end=$(date +%s.%N)
    python3 -c '
import json, sys
r = json.loads(sys.argv[1]); secs = float(sys.argv[2])
m = r["choices"][0]["message"]; u = r.get("usage", {})
print("Q:", sys.argv[3])
print("A:", (m.get("content") or "").strip()[:300].replace("\n", " "))
toks = u.get("completion_tokens", 0)
print(f"{toks} tokens in {secs:.1f}s  (~{toks/secs:.1f} tok/s end to end, incl. thinking)\n")
' "$resp" "$(echo "$end - $start" | bc)" "$prompt"
done
