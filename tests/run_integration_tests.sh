#!/usr/bin/env bash

set -euo pipefail

# Configuration
WORK_DIR="/tmp/llama-stack-integration-tests"
INFERENCE_MODEL="${INFERENCE_MODEL:-Qwen/Qwen3-0.6B}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get version dynamically from build.py (look in parent directory)
BUILD_PY="$SCRIPT_DIR/../distribution/build.py"
LLAMA_STACK_VERSION=$(grep '^CURRENT_LLAMA_STACK_VERSION' "$BUILD_PY" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
if [ -z "$LLAMA_STACK_VERSION" ]; then
    echo "Error: Could not extract llama-stack version from build.py"
    exit 1
fi

# Determine which repo to use based on version suffix
if [[ "$LLAMA_STACK_VERSION" == *"+rhai"* ]]; then
    LLAMA_STACK_REPO="https://github.com/opendatahub-io/llama-stack.git"
else
    LLAMA_STACK_REPO="https://github.com/llamastack/llama-stack.git"
fi

function clone_llama_stack() {
    # Clone the repository if it doesn't exist
    if [ ! -d "$WORK_DIR" ]; then
        git clone "$LLAMA_STACK_REPO" "$WORK_DIR"
    fi

    # Checkout the specific tag
    cd "$WORK_DIR"
    # fetch origin incase we didn't clone a fresh repo
    git fetch origin
    if ! git checkout "v$LLAMA_STACK_VERSION"; then
        echo "Error: Could not checkout tag v$LLAMA_STACK_VERSION"
        echo "Available tags:"
        git tag | grep "^v" | tail -10
        exit 1
    fi
}

function run_integration_tests() {
    echo "Running integration tests..."

    cd "$WORK_DIR"

    # Test to skip
    # TODO: re-enable the 2 chat_completion_non_streaming tests once they contain include max tokens (to prevent them from rambling)
    SKIP_TESTS="test_text_chat_completion_tool_calling_tools_not_in_request or test_text_chat_completion_structured_output or test_text_chat_completion_non_streaming or test_openai_chat_completion_non_streaming"

    # Dynamically determine the path to run.yaml from the original script directory
    STACK_CONFIG_PATH="$SCRIPT_DIR/../distribution/run.yaml"
    if [ ! -f "$STACK_CONFIG_PATH" ]; then
        echo "Error: Could not find stack config at $STACK_CONFIG_PATH"
        exit 1
    fi

    uv run --with llama-stack-client==0.3.0 pytest -s -v tests/integration/inference/ \
        --stack-config=server:"$STACK_CONFIG_PATH" \
        --text-model=vllm-inference/"$INFERENCE_MODEL" \
        --embedding-model=granite-embedding-125m \
        -k "not ($SKIP_TESTS)"
}

function main() {
    echo "Starting llama-stack integration tests"
    echo "Configuration:"
    echo "  LLAMA_STACK_VERSION: $LLAMA_STACK_VERSION"
    echo "  LLAMA_STACK_REPO: $LLAMA_STACK_REPO"
    echo "  WORK_DIR: $WORK_DIR"
    echo "  INFERENCE_MODEL: $INFERENCE_MODEL"

    clone_llama_stack
    run_integration_tests

    echo "Integration tests completed successfully!"
}


main "$@"
exit 0
