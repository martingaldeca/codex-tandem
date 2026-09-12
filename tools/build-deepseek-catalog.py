#!/usr/bin/env python3
"""Build a Codex model catalog for DeepSeek out of a local Codex installation.

Codex needs a model catalog that describes the models it can talk to. For
third-party providers you have to provide one yourself. Rather than shipping a
copy of Codex's instruction template in this repository, this script takes the
template that already exists in the local Codex installation and drops it into
the DeepSeek entries defined by assets/catalog/deepseek-catalog.template.json.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

PLACEHOLDER = "__CODEX_INSTRUCTIONS_TEMPLATE__"
PREFERRED_BASE_MODELS = (
    "gpt-5.6-luna",
    "gpt-5.6-sol",
    "gpt-5.6-terra",
    "gpt-5.5",
    "gpt-5.4",
)


def models_from_payload(payload):
    if isinstance(payload, dict):
        payload = payload.get("models", [])
    return [model for model in payload if isinstance(model, dict)]


def load_local_models(codex_bin: str, codex_home: str):
    env = dict(os.environ, CODEX_HOME=codex_home)
    try:
        proc = subprocess.run(
            [codex_bin, "debug", "models"],
            capture_output=True,
            text=True,
            env=env,
            timeout=120,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            models = models_from_payload(json.loads(proc.stdout))
            if models:
                return models, "codex debug models"
    except (OSError, ValueError, subprocess.SubprocessError):
        pass

    cache_path = os.path.join(codex_home, "models_cache.json")
    if os.path.isfile(cache_path):
        with open(cache_path, encoding="utf-8") as handle:
            models = models_from_payload(json.load(handle))
        if models:
            return models, cache_path

    raise SystemExit(
        "Could not read the local Codex model catalog. Tried `codex debug models` and "
        f"{cache_path}. Install or start Codex once, then retry."
    )


def configured_model(codex_home: str) -> str | None:
    config_path = os.path.join(codex_home, "config.toml")
    if not os.path.isfile(config_path):
        return None
    try:
        import tomllib

        with open(config_path, "rb") as handle:
            return tomllib.load(handle).get("model")
    except (ImportError, OSError, ValueError):
        pass
    match = re.search(r'^\s*model\s*=\s*"([^"]+)"', open(config_path, encoding="utf-8").read(), re.MULTILINE)
    return match.group(1) if match else None


def instructions_of(model: dict) -> str:
    template = model.get("model_messages", {}).get("instructions_template", "")
    return template or model.get("base_instructions", "") or ""


def pick_base_model(models, wanted: str | None, codex_home: str):
    by_slug = {model.get("slug"): model for model in models}
    if wanted:
        if wanted not in by_slug:
            raise SystemExit(f"Model '{wanted}' is not in the local Codex catalog.")
        if not instructions_of(by_slug[wanted]):
            raise SystemExit(f"Model '{wanted}' has no instruction template to reuse.")
        return by_slug[wanted]

    candidates = (configured_model(codex_home), *PREFERRED_BASE_MODELS)
    for slug in candidates:
        model = by_slug.get(slug) if slug else None
        if model and instructions_of(model):
            return model
    for model in models:
        if instructions_of(model):
            return model
    raise SystemExit("No model in the local Codex catalog provides an instruction template.")


def fill_placeholders(node, instructions: str):
    if isinstance(node, dict):
        return {key: fill_placeholders(value, instructions) for key, value in node.items()}
    if isinstance(node, list):
        return [fill_placeholders(item, instructions) for item in node]
    if node == PLACEHOLDER:
        return instructions
    return node


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, help="Path to deepseek-catalog.template.json")
    parser.add_argument("--output", required=True, help="Where to write the generated catalog")
    parser.add_argument("--codex-bin", default=os.environ.get("CODEX_BIN", "codex"))
    parser.add_argument(
        "--codex-home",
        default=os.environ.get("CODEX_SOURCE_HOME", os.path.expanduser("~/.codex")),
        help="Codex home used to read the local model catalog (default: ~/.codex)",
    )
    parser.add_argument(
        "--base-model",
        default=None,
        help="Model whose instruction template is reused (default: the model configured in config.toml)",
    )
    args = parser.parse_args()

    if shutil.which(args.codex_bin) is None and not os.path.isfile(args.codex_bin):
        raise SystemExit(f"Codex binary '{args.codex_bin}' not found.")

    with open(args.template, encoding="utf-8") as handle:
        template = json.load(handle)

    models, source = load_local_models(args.codex_bin, args.codex_home)
    base = pick_base_model(models, args.base_model, args.codex_home)
    instructions = instructions_of(base)
    if len(instructions) < 1000:
        raise SystemExit(
            f"Instruction template from '{base.get('slug')}' looks too short "
            f"({len(instructions)} chars); pass --base-model explicitly."
        )

    catalog = fill_placeholders(template, instructions)
    slugs = [model.get("slug") for model in catalog.get("models", [])]
    if not slugs or not all(instructions_of(model) for model in catalog.get("models", [])):
        raise SystemExit("Generated catalog is missing model entries or instruction templates.")

    directory = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(directory, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, indent=2)
        handle.write("\n")

    print(f"catalog: {args.output}")
    print(f"  models      : {', '.join(str(slug) for slug in slugs)}")
    print(f"  instructions: {len(instructions)} chars from '{base.get('slug')}' ({source})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
