#!/usr/bin/env python3

import argparse
import json
import os
import re
from typing import Any


def camel_case_from_file(path: str) -> str:
    base = os.path.basename(path)
    name = re.sub(r"\.json$", "", base, flags=re.IGNORECASE)
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[-_]+", name) if part)


def remove_format_fields(value: Any, formats_to_remove: set[str]) -> Any:
    if isinstance(value, dict):
        output = {}
        for key, child in value.items():
            if key == "format" and child in formats_to_remove:
                continue
            output[key] = remove_format_fields(child, formats_to_remove)
        return output

    if isinstance(value, list):
        return [remove_format_fields(child, formats_to_remove) for child in value]

    return value


def replace_operation_tags(value: Any, tag_name: str) -> Any:
    if isinstance(value, dict):
        output = {}
        for key, child in value.items():
            if key == "tags" and isinstance(child, list) and (not child or isinstance(child[0], str)):
                output[key] = [tag_name]
            else:
                output[key] = replace_operation_tags(child, tag_name)
        return output

    if isinstance(value, list):
        return [replace_operation_tags(child, tag_name) for child in value]

    return value


def main() -> None:
    parser = argparse.ArgumentParser(description="Normalize OpenAPI JSON before Swift generation.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--api-name")
    parser.add_argument("--tag-strategy", choices=["fileName", "preserve"], default="fileName")
    parser.add_argument(
        "--remove-format",
        action="append",
        default=["date", "date-time"],
        help="Schema format value to remove. Can be passed multiple times.",
    )
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8-sig") as file:
        data = json.load(file)

    data = remove_format_fields(data, set(args.remove_format))

    if args.tag_strategy == "fileName":
        api_name = args.api_name or camel_case_from_file(args.input)
        data = replace_operation_tags(data, api_name)
        if isinstance(data, dict):
            data["tags"] = [{"name": api_name, "description": f"Unified {api_name}"}]

    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=2, ensure_ascii=False)
        file.write("\n")


if __name__ == "__main__":
    main()
