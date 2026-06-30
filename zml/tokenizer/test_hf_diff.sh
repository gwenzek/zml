#!/usr/bin/env bash
set -exuo pipefail

input="${1:-./zml/tokenizer/main.zig}"
hf_json="${HF_JSON:-/tmp/zml_hf_tokens.json}"
hf_out="${HF_OUT:-/tmp/hf_tokens.txt}"
zml_out="${ZML_OUT:-/tmp/zml_tokens.txt}"
zml_err="${ZML_ERR:-/tmp/zml_tokens.err}"

uv run zml/tokenizer/test_hf.py --json < "$input" > "$hf_json"
tokenizer="$(
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tokenizer_file"])' "$hf_json"
)"

uv run zml/tokenizer/test_hf.py < "$input" > "$hf_out"

bazel build //zml/tokenizer:main
bazel-bin/zml/tokenizer/main --tokenizer="$tokenizer" < "$input" > "$zml_out" 2> "$zml_err"

wc -l "$hf_out" "$zml_out"
diff -u "$hf_out" "$zml_out"
