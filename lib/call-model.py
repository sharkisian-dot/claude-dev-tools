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


# ── Cost logging ─────────────────────────────────────────────────────────────
PRICING: dict[str, tuple[float, float]] = {
    # model: (input_price_per_1M, output_price_per_1M)
    "gemini-2.5-pro": (1.25, 10.0),
    "gemini-2.5-flash": (0.075, 0.30),
    "gemini-2.0-flash": (0.10, 0.40),
    "gpt-5.4-2026-03-05": (2.50, 10.0),
    "gpt-4.1": (2.00, 8.0),
    "gpt-4o": (2.50, 10.0),
    "gpt-4o-mini": (0.15, 0.60),
}


def _log_cost(provider: str, model: str, usage: dict) -> None:
    log_file = os.environ.get("COST_LOG_FILE")
    if not log_file:
        return
    import datetime
    prompt_tokens = usage.get("promptTokenCount") or usage.get("prompt_tokens") or 0
    completion_tokens = usage.get("candidatesTokenCount") or usage.get("completion_tokens") or 0
    total_tokens = usage.get("totalTokenCount") or usage.get("total_tokens") or (prompt_tokens + completion_tokens)
    pricing = PRICING.get(model)
    if pricing:
        cost_usd: float | None = (prompt_tokens * pricing[0] + completion_tokens * pricing[1]) / 1_000_000
    else:
        print(f"[cost] Unknown model '{model}' — cost not calculated", file=sys.stderr)
        cost_usd = None
    entry = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "provider": provider,
        "model": model,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "cost_usd": cost_usd,
    }
    try:
        with open(log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


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
            _log_cost("gemini", model, data.get("usageMetadata", {}))
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
            _log_cost("openai", model, data.get("usage", {}))
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
