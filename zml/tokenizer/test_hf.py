# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "sentencepiece>=0.2.0",
#   "transformers>=4.53.0",
# ]
# ///

import argparse
import json
import os
import sys

from transformers import AutoTokenizer
from transformers.utils import cached_file


DEFAULT_MODEL_ID = "google/gemma-4-31B-it"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Tokenize text with a HuggingFace tokenizer only."
    )
    parser.add_argument(
        "text",
        nargs="*",
        help="Text to tokenize. If omitted, text is read from stdin.",
    )
    parser.add_argument(
        "--model-id",
        default=DEFAULT_MODEL_ID,
        help=f"HuggingFace tokenizer repo to load. Default: {DEFAULT_MODEL_ID}",
    )
    parser.add_argument(
        "--no-special-tokens",
        action="store_true",
        help="Do not add tokenizer-specific special tokens.",
    )
    parser.add_argument(
        "--show-tokens",
        action="store_true",
        help="Also print the string token for each token id.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print a JSON payload instead of a human-readable summary.",
    )
    return parser.parse_args()


def get_input_text(args: argparse.Namespace) -> str:
    if args.text:
        return " ".join(args.text)

    text = sys.stdin.read()
    if not text:
        raise SystemExit("No text provided. Pass text as arguments or via stdin.")
    return text


def find_tokenizer_file(model_id: str, tokenizer) -> str | None:
    for filename in ("tokenizer.json", "tokenizer.model"):
        path = cached_file(
            model_id,
            filename,
            _raise_exceptions_for_gated_repo=False,
            _raise_exceptions_for_missing_entries=False,
        )
        if path:
            return path

    for key in ("tokenizer_file", "vocab_file"):
        path = tokenizer.init_kwargs.get(key)
        if isinstance(path, str) and os.path.exists(path):
            return path

    path = getattr(tokenizer, "vocab_file", None)
    if isinstance(path, str) and os.path.exists(path):
        return path

    return None


def escape_token_text(text: str) -> str:
    text = text.replace("▁", " ")
    escaped = []
    for char in text:
        if char == "\n":
            escaped.append("\\n")
        elif char == "\r":
            escaped.append("\\r")
        elif char == "\t":
            escaped.append("\\t")
        elif char == "\\":
            escaped.append("\\\\")
        elif ord(char) < 0x20 or ord(char) == 0x7F:
            escaped.append(f"\\x{ord(char):02X}")
        else:
            escaped.append(char)
    return "".join(escaped)


def main() -> None:
    args = parse_args()
    text = get_input_text(args)

    # AutoTokenizer downloads tokenizer/config files only. It does not fetch model weights.
    tokenizer = AutoTokenizer.from_pretrained(args.model_id, use_fast=True)
    tokenizer_file = find_tokenizer_file(args.model_id, tokenizer)
    token_ids = tokenizer.encode(text, add_special_tokens=not args.no_special_tokens)

    payload = {
        "model_id": args.model_id,
        "tokenizer_file": tokenizer_file,
        "text": text,
        "token_count": len(token_ids),
        "token_ids": token_ids,
    }
    if args.show_tokens:
        payload["tokens"] = tokenizer.convert_ids_to_tokens(token_ids)

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    for token_id, token_text in zip(token_ids, tokenizer.convert_ids_to_tokens(token_ids)):
        print(f"{token_id} {escape_token_text(token_text)}")


if __name__ == "__main__":
    main()
