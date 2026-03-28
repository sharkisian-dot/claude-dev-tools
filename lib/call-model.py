#!/usr/bin/env python3
"""
call-model — Universal model caller for review-pr
Reads full prompt+context from stdin, writes response to stdout.

Usage:
  python3 tools/devtools/lib/call-model.py --provider gemini --model gemini-2.5-flash
  python3 tools/devtools/lib/call-model.py --provider openai --model gpt-4o
"""
import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error


def call_gemini(prompt: str, model: str) -> str:
    api_key = os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GOOGLE_API_KEY not set")

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    payload = json.dumps({
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"maxOutputTokens": 8192},
    }).encode("utf-8")

    req = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )

    last_err: Exception = RuntimeError("unknown")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            parts = (
                data.get("candidates", [{}])[0]
                .get("content", {})
                .get("parts", [])
            )
            text_parts = [p["text"] for p in parts if p.get("text") and not p.get("thought")]
            if not text_parts:
                raise RuntimeError(f"Gemini empty response (finishReason: {data.get('candidates', [{}])[0].get('finishReason')})")
            return text_parts[-1]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            last_err = RuntimeError(f"Gemini HTTP {e.code}: {body[:300]}")
            if e.code == 429 and attempt < 2:
                delay = 2 ** attempt * 3
                print(f"Rate limited — retrying in {delay}s...", file=sys.stderr)
                time.sleep(delay)
                continue
            raise last_err
        except urllib.error.URLError as e:
            last_err = RuntimeError(f"Gemini network error: {e.reason}")
            if attempt < 2:
                time.sleep(2 ** attempt * 2)
                continue
            raise last_err
    raise last_err


def call_openai(prompt: str, model: str) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set")

    url = "https://api.openai.com/v1/chat/completions"
    # Newer models (gpt-5.x, o1, o3, o4) use max_completion_tokens
    _newer_prefixes = ("gpt-5", "o1", "o3", "o4")
    tokens_key = "max_completion_tokens" if any(model.startswith(p) for p in _newer_prefixes) else "max_tokens"
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        tokens_key: 8192,
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )

    last_err: Exception = RuntimeError("unknown")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            return data["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            last_err = RuntimeError(f"OpenAI HTTP {e.code}: {body[:300]}")
            if e.code in (429, 503) and attempt < 2:
                delay = 2 ** attempt * 3
                print(f"Rate limited — retrying in {delay}s...", file=sys.stderr)
                time.sleep(delay)
                continue
            raise last_err
        except urllib.error.URLError as e:
            last_err = RuntimeError(f"OpenAI network error: {e.reason}")
            if attempt < 2:
                time.sleep(2 ** attempt * 2)
                continue
            raise last_err
    raise last_err


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Call Gemini or OpenAI API with stdin as the prompt"
    )
    parser.add_argument("--provider", required=True, choices=["gemini", "openai"])
    parser.add_argument("--model", required=True, help="Model name (e.g. gemini-2.5-flash, gpt-4o)")
    args = parser.parse_args()

    prompt = sys.stdin.read()
    if not prompt.strip():
        print("ERROR: empty prompt on stdin", file=sys.stderr)
        sys.exit(1)

    try:
        if args.provider == "gemini":
            result = call_gemini(prompt, args.model)
        else:
            result = call_openai(prompt, args.model)
        sys.stdout.write(result)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
