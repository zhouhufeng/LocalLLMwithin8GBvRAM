#!/bin/bash
# Build Prism ML's llama.cpp fork (llama-server only) for Pascal GPUs (GTX 10xx, sm_61)
# and install it into the Bonsai-demo's bin/cuda, backing up the prebuilt first.
#
# Usage: ./build_llamacpp_sm61.sh /path/to/Bonsai-demo
# Env:   CUDA_ARCH (default 61)  JOBS (default 6)  CUDA_HOST_CXX (e.g. g++-12, optional)
set -euo pipefail

DEMO="$(cd "${1:?usage: $0 /path/to/Bonsai-demo}" && pwd)"
ARCH="${CUDA_ARCH:-61}"
JOBS="${JOBS:-6}"
SRC="$DEMO/llama.cpp"
BUILD="$SRC/build-sm$ARCH"

command -v nvcc >/dev/null || { echo "nvcc not found: install the CUDA toolkit" >&2; exit 1; }

if [ ! -d "$SRC" ]; then
    git clone https://github.com/PrismML-Eng/llama.cpp.git "$SRC"
    echo "Note: check out the commit pinned by Bonsai-demo's setup.sh if the start script complains."
fi

# cmake/ninja: use system ones if present, else a throwaway venv
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
    TOOLS="$(mktemp -d)/buildtools"
    python3 -m venv "$TOOLS" && "$TOOLS/bin/pip" install -q cmake ninja
    export PATH="$TOOLS/bin:$PATH"
fi

EXTRA=()
[ -n "${CUDA_HOST_CXX:-}" ] && EXTRA+=("-DCMAKE_CUDA_HOST_COMPILER=$CUDA_HOST_CXX")

cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$ARCH" \
    -DCMAKE_CUDA_COMPILER="$(command -v nvcc)" \
    -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF "${EXTRA[@]}"
cmake --build "$BUILD" --target llama-server -j "$JOBS"

cd "$DEMO"
if [ -d bin/cuda ] && [ ! -d bin/cuda.prebuilt-backup ]; then
    mv bin/cuda bin/cuda.prebuilt-backup
fi
rm -rf bin/cuda && mkdir -p bin/cuda
cp -a "$BUILD/bin/." bin/cuda/
LD_LIBRARY_PATH=bin/cuda bin/cuda/llama-server --version 2>&1 | tail -2
echo "Installed sm_$ARCH llama-server into $DEMO/bin/cuda"
