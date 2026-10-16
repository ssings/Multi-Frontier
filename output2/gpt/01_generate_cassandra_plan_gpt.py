from __future__ import annotations

import html
import os
import re
import time
import urllib.error
import urllib.request
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List, Tuple

from openai import OpenAI

# ============================== GPT / OpenAI Fixed Configuration ==============================
# This script is only for Stage 1 of the Cassandra GPT experiment: official materials and specification generation.
#
# Before use, please change the placeholder values below to your exact GPT API model ID,
# or set the environment variable OPENAI_MODEL.
# The API Key is always read from OPENAI_API_KEY.
MODEL = os.getenv(
    "OPENAI_MODEL",
    "gpt-5.6-terra",
).strip()

PROVIDER = "openai"
MODEL_FAMILY = "gpt"
BASE_URL = os.getenv(
    "OPENAI_BASE_URL",
    "https://api.openai.com/v1",
).strip()
API_KEY_ENV = "OPENAI_API_KEY"
REASONING_EFFORT = os.getenv(
    "OPENAI_REASONING_EFFORT",
    "high",
).strip()

API_TIMEOUT_SECONDS = int(os.getenv("CASSANDRA_SPEC_TIMEOUT", "900"))
MAX_OUTPUT_TOKENS = int(os.getenv("CASSANDRA_SPEC_MAX_OUTPUT_TOKENS", "24000"))
API_RETRIES = int(os.getenv("CASSANDRA_SPEC_API_RETRIES", "3"))

DOC_FETCH_TIMEOUT = int(os.getenv("CASSANDRA_DOC_FETCH_TIMEOUT", "45"))
MIN_SUCCESS_SOURCES = int(os.getenv("CASSANDRA_MIN_DOC_SOURCES", "5"))
MAX_CHARS_PER_SOURCE = int(os.getenv("CASSANDRA_MAX_CHARS_PER_SOURCE", "30000"))
MAX_DOC_PROMPT_CHARS = int(os.getenv("CASSANDRA_MAX_DOC_PROMPT_CHARS", "180000"))
SPEC_REPAIR_LIMIT = int(os.getenv("CASSANDRA_SPEC_REPAIR_LIMIT", "3"))

DOC_SOURCES: List[Tuple[str, str]] = [
    (
        "Architecture Overview",
        "https://cassandra.apache.org/doc/latest/cassandra/architecture/overview.html",
    ),
    (
        "Dynamo and Tunable Consistency",
        "https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html",
    ),
    (
        "Storage Engine and Write Path",
        "https://cassandra.apache.org/doc/latest/cassandra/architecture/storage-engine.html",
    ),
    (
        "Guarantees and Eventual Consistency",
        "https://cassandra.apache.org/doc/latest/cassandra/architecture/guarantees.html",
    ),
    (
        "Authentication and Authorization",
        "https://cassandra.apache.org/doc/latest/cassandra/managing/operating/security.html",
    ),
    (
        "Roles and Permissions",
        "https://cassandra.apache.org/doc/latest/cassandra/developing/cql/security.html",
    ),
    (
        "Topology Changes",
        "https://cassandra.apache.org/doc/latest/cassandra/managing/operating/topo_changes.html",
    ),
    (
        "Streaming",
        "https://cassandra.apache.org/doc/latest/cassandra/architecture/streaming.html",
    ),
]

REQUIRED_SPEC_SECTIONS: Dict[str, Tuple[str, ...]] = {
    "Modeling Scope": ("Modeling Scope", "Abstraction Scope", "Not Modeled"),
    "Authorization": ("Authorization", "Authentication", "Permission", "role"),
    "Write and Commit": ("Write", "Commit", "commit log", "commitlog"),
    "Replica Synchronization": ("Replica", "Synchronization", "Replication", "replica"),
    "Consistency Read": ("Consistency Read", "Read Consistency", "consistency level", "quorum"),
    "Data Migration": ("Migration", "streaming", "bootstrap", "decommission", "token range"),
    "Frontier": ("frontier", "Frontier"),
    "Verification Goals": ("Verification Goals", "Safety Properties", "Invariants", "Liveness"),
}


def find_project_root() -> Path:
    start = Path(__file__).resolve().parent
    for candidate in [start, *start.parents]:
        if (
            (candidate / "docs").is_dir()
            and (candidate / "milvus").is_dir()
            and (candidate / "output1").is_dir()
        ):
            return candidate
    raise FileNotFoundError(
        "Unable to locate the project root directory. Please ensure that docs, milvus, and output1 exist in the project."
    )


ROOT = find_project_root()
DOCS_DIR = ROOT / "docs"
OUTPUT1_DIR = ROOT / "output1"
OUTPUT2_DIR = ROOT / "output2"
FAMILY_DIR = OUTPUT2_DIR / "gpt"

FRONTIER_PATH = DOCS_DIR / "Frontier_Method.md"
QDRANT_SPEC_CANDIDATES = [
    DOCS_DIR / "Qdrant_Specification.md",
    OUTPUT1_DIR / "Qdrant_Specification.md",
]

RUN_DIR = FAMILY_DIR / "__pending__" / "stage1"
DOCS_OUTPUT_PATH = RUN_DIR / "cassandra_official_docs.md"
SPEC_OUTPUT_PATH = RUN_DIR / "Cassandra_Specification.md"
MANIFEST_PATH = RUN_DIR / "source_manifest.txt"
RESULT_PATH = RUN_DIR / "result.txt"
ERROR_DIR = RUN_DIR / "error"

class PipelineError(RuntimeError):
    pass


class VisibleTextParser(HTMLParser):
    SKIP_TAGS = {"script", "style", "svg", "nav", "footer", "header", "noscript"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.parts: List[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() in self.SKIP_TAGS:
            self.skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.SKIP_TAGS and self.skip_depth > 0:
            self.skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.skip_depth == 0:
            value = re.sub(r"\s+", " ", data).strip()
            if value:
                self.parts.append(value)

    def text(self) -> str:
        joined = "\n".join(self.parts)
        joined = html.unescape(joined)
        joined = re.sub(r"\n{3,}", "\n\n", joined)
        return joined.strip()


def now_text() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        return path.read_text(encoding="gb18030")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def normalize_error_stage(stage: str) -> str:
    normalized = re.sub(
        r"[^a-z0-9_]+",
        "_",
        stage.strip().lower(),
    ).strip("_")
    return normalized or "unknown"


def next_error_index() -> int:
    if not ERROR_DIR.is_dir():
        return 1
    indexes: List[int] = []
    for path in ERROR_DIR.glob("err[0-9][0-9]_*.txt"):
        match = re.match(r"err(\d+)_", path.name)
        if match:
            indexes.append(int(match.group(1)))
    return max(indexes, default=0) + 1


def append_error(stage: str, details: str) -> Path:
    index = next_error_index()
    stage_name = normalize_error_stage(stage)
    error_path = ERROR_DIR / f"err{index:02d}_{stage_name}.txt"
    content = (
        f"time={now_text()}\n"
        f"stage={stage}\n"
        f"model={MODEL}\n"
        f"error_index={index}\n"
        f"\n===== DETAILS =====\n"
        f"{details}\n"
    )
    write_text(error_path, content)
    return error_path

def choose_existing(paths: List[Path]) -> Path:
    for path in paths:
        if path.is_file():
            return path
    raise FileNotFoundError(
        "Qdrant规约.md not found, checked: \n" + "\n".join(str(p) for p in paths)
    )


def validate_inputs() -> Path:
    required = [FRONTIER_PATH]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing input files: \n" + "\n".join(missing))
    if (
        not MODEL
        or MODEL == "REPLACE_WITH_YOUR_GPT_MODEL_ID"
    ):
        raise EnvironmentError(
            "Please first set the exact OPENAI_MODEL, or modify MODEL at the top of the script."
        )
    if not BASE_URL:
        raise EnvironmentError("OPENAI_BASE_URL / BASE_URL cannot be empty.")
    if not os.getenv(API_KEY_ENV):
        raise EnvironmentError(
            f"API Key environment variable not set: {API_KEY_ENV}."
        )
    OUTPUT2_DIR.mkdir(parents=True, exist_ok=True)
    return choose_existing(QDRANT_SPEC_CANDIDATES)


def create_next_stage1_run() -> Tuple[Path, int]:
    """
    Create output2/ds/<number>/stage1.
    The first run is 01, the second is 02, and so on.
    """
    FAMILY_DIR.mkdir(parents=True, exist_ok=True)
    existing = [
        int(path.name)
        for path in FAMILY_DIR.iterdir()
        if path.is_dir() and re.fullmatch(r"\d{2,}", path.name)
    ]
    next_index = max(existing, default=0) + 1
    while True:
        experiment_dir = FAMILY_DIR / f"{next_index:02d}"
        try:
            experiment_dir.mkdir(parents=False, exist_ok=False)
            stage1_dir = experiment_dir / "stage1"
            stage1_dir.mkdir(parents=False, exist_ok=False)
            return stage1_dir, next_index
        except FileExistsError:
            next_index += 1


def parse_key_value_file(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line in read_text(path).splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def configure_run_paths(run_dir: Path) -> None:
    global RUN_DIR, DOCS_OUTPUT_PATH, SPEC_OUTPUT_PATH, MANIFEST_PATH, RESULT_PATH, ERROR_DIR
    RUN_DIR = run_dir
    DOCS_OUTPUT_PATH = RUN_DIR / "cassandra_official_docs.md"
    SPEC_OUTPUT_PATH = RUN_DIR / "Cassandra Specification.md"
    MANIFEST_PATH = RUN_DIR / "source_manifest.txt"
    RESULT_PATH = RUN_DIR / "result.txt"
    ERROR_DIR = RUN_DIR / "error"

def fetch_url(title: str, url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 CassandraFormalizationResearch/1.0 "
                "(official documentation retrieval)"
            )
        },
    )
    with urllib.request.urlopen(request, timeout=DOC_FETCH_TIMEOUT) as response:
        raw = response.read()
        charset = response.headers.get_content_charset() or "utf-8"
    source = raw.decode(charset, errors="replace")
    parser = VisibleTextParser()
    parser.feed(source)
    text = parser.text()
    if len(text) < 500:
        raise PipelineError(f"{title} fetched content too short: {len(text)} characters")
    return text[:MAX_CHARS_PER_SOURCE]


def fetch_official_docs() -> Tuple[List[Tuple[str, str, str]], List[Tuple[str, str, str]]]:
    successes: List[Tuple[str, str, str]] = []
    failures: List[Tuple[str, str, str]] = []
    for title, url in DOC_SOURCES:
        print(f"Fetching official documentation: {title}")
        try:
            text = fetch_url(title, url)
            successes.append((title, url, text))
        except Exception as exc:
            failures.append((title, url, str(exc)))
            print(f"  Fetch failed: {exc}")
    return successes, failures


def build_docs_file(
    successes: List[Tuple[str, str, str]],
    failures: List[Tuple[str, str, str]],
) -> str:
    lines = [
        "# Cassandra Official Documentation Snapshot",
        "",
        f"Fetch time: {now_text()}",
        "Sources limited to Apache Cassandra official documentation.",
        "",
    ]
    for title, url, text in successes:
        lines.extend(
            [
                f"## {title}",
                "",
                f"Source: {url}",
                "",
                text,
                "",
            ]
        )
    if failures:
        lines.extend(["# Sources not successfully fetched", ""])
        for title, url, error in failures:
            lines.append(f"- {title} | {url} | {error}")
    return "\n".join(lines).strip() + "\n"


def build_manifest(
    successes: List[Tuple[str, str, str]],
    failures: List[Tuple[str, str, str]],
) -> str:
    lines = [f"fetched_at={now_text()}"]
    for title, url, _ in successes:
        lines.append(f"pass\t{title}\t{url}")
    for title, url, error in failures:
        lines.append(f"fail\t{title}\t{url}\t{error}")
    return "\n".join(lines) + "\n"


def create_client() -> OpenAI:
    return OpenAI(
        api_key=os.environ[API_KEY_ENV],
        base_url=BASE_URL,
        timeout=API_TIMEOUT_SECONDS,
        max_retries=0,
    )


def _usage_from_response(response) -> Dict[str, int]:
    usage = getattr(response, "usage", None)
    return {
        "prompt_tokens": int(getattr(usage, "input_tokens", 0) or 0),
        "completion_tokens": int(getattr(usage, "output_tokens", 0) or 0),
        "total_tokens": int(getattr(usage, "total_tokens", 0) or 0),
    }


def call_model(
    client: OpenAI,
    prompt: str,
) -> Tuple[str, Dict[str, int]]:
    last_error: Exception | None = None
    system_prompt = (
        "You are an expert in distributed databases and TLA+ formal modeling."
        "Your task is to form a faithful, implementable natural-language modeling specification from official materials."
    )

    for attempt in range(1, API_RETRIES + 1):
        try:
            response = client.responses.create(
                model=MODEL,
                instructions=system_prompt,
                input=prompt,
                max_output_tokens=MAX_OUTPUT_TOKENS,
                reasoning={"effort": REASONING_EFFORT},
                store=False,
            )
            content = getattr(response, "output_text", "") or ""
            usage_dict = _usage_from_response(response)

            if not content.strip():
                raise PipelineError(
                    f"Model {MODEL_FAMILY}/{MODEL} returned empty content."
                )
            return content, usage_dict

        except Exception as exc:
            last_error = exc
            print(
                f"API call failed ({attempt}/{API_RETRIES}):"
                f"{type(exc).__name__}: {exc}"
            )

            status_code = getattr(exc, "status_code", None)
            if status_code is not None and 400 <= int(status_code) < 500:
                break
            if attempt >= API_RETRIES:
                break

            wait_seconds = min(30, 2 ** attempt)
            print(f"Retrying after waiting {wait_seconds} seconds.")
            time.sleep(wait_seconds)

    if last_error is not None:
        raise PipelineError(
            f"Model {MODEL_FAMILY}/{MODEL} API call ultimately failed:"
            f"{type(last_error).__name__}: {last_error}"
        )
    raise PipelineError(
        f"Model {MODEL_FAMILY}/{MODEL} API call ultimately failed."
    )


def clean_spec_response(text: str) -> str:
    value = text.strip()
    value = re.sub(r"^```(?:markdown|md|text)?\s*", "", value, flags=re.I)
    value = re.sub(r"\s*```$", "", value)
    marker = re.search(
        r"(?is)===== FILE:\s*Cassandra Specification\.md\s*=====\s*(.*?)"
        r"(?:===== END FILE =====|$)",
        value,
    )
    if marker:
        value = marker.group(1).strip()
    return value + "\n"


def spec_structure_errors(spec: str) -> List[str]:
    lower = spec.lower()
    errors: List[str] = []
    if len(spec.strip()) < 2500:
        errors.append("Specification content too short; did not form sufficient modeling design.")
    for section, keywords in REQUIRED_SPEC_SECTIONS.items():
        if not any(keyword.lower() in lower for keyword in keywords):
            errors.append(f"Missing or not clearly covered: {section}")
    if "qdrant" in lower and lower.count("qdrant") > 6:
        errors.append("The specification retains too many Qdrant-specific expressions, posing a risk of direct copying.")
        if "official" not in spec and "source" not in spec:
        errors.append("The specification does not state that the main semantics come from Cassandra official documentation.")
    return errors


def build_initial_spec_prompt(qdrant_spec_path: Path, official_docs: str) -> str:
    docs_for_prompt = official_docs[:MAX_DOC_PROMPT_CHARS]
    return f"""
Please generate a Chinese natural-language file "Cassandra Specification.md" for the next-stage automatic generation
Cassandra's TLA+ model and TLC configuration.

[Positioning]
- This is a formal modeling design specification for Cassandra, not a product description, and not TLA+ code.
- Cassandra business semantics must come from the provided Apache Cassandra official documentation.
- The Qdrant specification is used only for reference in chapter organization, abstraction granularity, and expression style, and must not copy
  Qdrant-specific semantics such as Collection, Point, ShardMigrate.
- The Frontier method is used to organize visibility boundaries for writes, commits, replicas, reads, and migration.

【Must cover】
1. Modeling goals, abstraction scope, and explicitly not modeled content.
2. Cassandra entities: roles/subjects, nodes, token range or equivalent data range,
   replicas, data items, coordinator nodes, and necessary mappings.
3. Authorization and rejection operations.
4. Write path: coordination, target replicas, commit log, memtable/applied state,
   replica acknowledgements, write consistency levels, and commit conditions.
5. Abstractions for replica propagation, late replicas, or eventual synchronization.
6. Consistent reads: representative levels such as ONE, QUORUM, ALL, and return conditions.
7. Data range migration: bootstrap, decommission, move/replace, or streaming
   unified abstraction, and clarify migration phases and ownership switching conditions.
8. Frontier layered definitions and their relationship with read results.
9. Safety properties to be verified, and explain which liveness properties require fairness.
10. Official documentation basis for each major scenario.
11. Suggest module partitioning for subsequent model generation, but do not output TLA+ code and cfg.

【Output requirements】
- Output only the body of Cassandra_Specification.md.
- Do not output Markdown code fences.
- Do not claim that manual logic checks have been performed.

================ Frontier Method.md ================
{read_text(FRONTIER_PATH)}

================ Qdrant specification.md (for format reference only) ================
{read_text(qdrant_spec_path)}

================ Cassandra official documentation materials ================
{docs_for_prompt}
""".strip()


def build_repair_prompt(spec: str, errors: List[str], official_docs: str) -> str:
    return f"""
Please revise the following 《Cassandra specification.md》, fixing only structural omissions and obvious cross-database copy-paste issues.

Current automated check issues:
{chr(10).join(f"- {e}" for e in errors)}

Requirements:
- Preserve Cassandra official documentation semantics;
- Complete authorization, write commit, replica synchronization, consistency read, data range migration,
  Frontier, verification objectives, and out-of-model scope;
- Do not output explanations or code fences; output only the revised complete specification body.

Current specification:
{spec}

Official documentation summary:
{official_docs[:80000]}
""".strip()


def write_result(values: Dict[str, object]) -> None:
    order = [
        "model_family",
        "provider",
        "model",
        "base_url",
        "repeat_index",
        "started_at",
        "docs_result",
        "spec_result",
        "failed_checks",
        "docs_reason",
        "spec_reason",
        "fetched_sources",
        "failed_sources",
        "api_calls",
        "spec_repair_rounds",
        "prompt_tokens",
        "completion_tokens",
        "total_tokens",
        "finished_at",
    ]
    lines: List[str] = []
    for key in order:
        if key in values:
            lines.append(f"{key}={values[key]}")
    write_text(RESULT_PATH, "\n".join(lines) + "\n")


def run_one_stage(qdrant_spec_path: Path) -> Dict[str, object]:
    started_at = now_text()
    run_dir, repeat_index = create_next_stage1_run()
    configure_run_paths(run_dir)
    print(f"Current stage-one directory: {run_dir}")

    result: Dict[str, object] = {
        "model_family": MODEL_FAMILY,
        "provider": PROVIDER,
        "model": MODEL,
        "base_url": BASE_URL,
        "repeat_index": f"{repeat_index:02d}",
        "started_at": started_at,
        "docs_result": "not_run",
        "spec_result": "not_run",
        "failed_checks": "none",
        "fetched_sources": 0,
        "failed_sources": 0,
        "api_calls": 0,
        "spec_repair_rounds": 0,
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
    }

    try:
        successes, failures = fetch_official_docs()
        result["fetched_sources"] = len(successes)
        result["failed_sources"] = len(failures)

        docs_text = build_docs_file(successes, failures)
        write_text(DOCS_OUTPUT_PATH, docs_text)
        write_text(MANIFEST_PATH, build_manifest(successes, failures))

        if len(successes) < MIN_SUCCESS_SOURCES:
            result["docs_result"] = "fail"
            result["spec_result"] = "not_run"
            result["failed_checks"] = "docs"
            result["docs_reason"] = (
                f"Successfully obtained only {len(successes)} official sources,"
                f"below the minimum requirement {MIN_SUCCESS_SOURCES}."
            )
            append_error("docs", str(result["docs_reason"]))
            return result

        result["docs_result"] = "pass"
        client = create_client()
        prompt = build_initial_spec_prompt(qdrant_spec_path, docs_text)
        response, usage = call_model(client, prompt)
        result["api_calls"] = int(result["api_calls"]) + 1
        for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
            result[key] = int(result[key]) + usage[key]

        spec = clean_spec_response(response)
        errors = spec_structure_errors(spec)
        repair_rounds = 0
        while errors and repair_rounds < SPEC_REPAIR_LIMIT:
            append_error("spec_structure", "；".join(errors))
            repair_rounds += 1
            print(
                f"Cassandra specification structure repair "
                f"{repair_rounds}/{SPEC_REPAIR_LIMIT}："
                + "；".join(errors)
            )
            response, usage = call_model(
                client,
                build_repair_prompt(spec, errors, docs_text),
            )
            result["api_calls"] = int(result["api_calls"]) + 1
            for key in (
                "prompt_tokens", "completion_tokens", "total_tokens"
            ):
                result[key] = int(result[key]) + usage[key]
            spec = clean_spec_response(response)
            errors = spec_structure_errors(spec)

        result["spec_repair_rounds"] = repair_rounds
        write_text(SPEC_OUTPUT_PATH, spec)
        if errors:
            result["spec_result"] = "fail"
            result["failed_checks"] = "spec"
            result["spec_reason"] = "；".join(errors)
            append_error("spec_final", str(result["spec_reason"]))
            return result

        result["spec_result"] = "pass"
        result["failed_checks"] = "none"
        print(
            f"{MODEL_FAMILY}/{repeat_index:02d}/stage1 official documentation and specification generation completed."
        )
        return result

    except Exception as exc:
        failed: List[str] = []
        if result["docs_result"] != "pass":
            result["docs_result"] = "fail"
            result["docs_reason"] = str(exc).splitlines()[0][:500]
            failed.append("docs")
        else:
            result["spec_result"] = "fail"
            result["spec_reason"] = str(exc).splitlines()[0][:500]
            failed.append("spec")
        result["failed_checks"] = ",".join(failed) if failed else "process"
        append_error("pipeline", str(exc))
        print(f"{MODEL_FAMILY}/{repeat_index:02d}/stage1 exception: {exc}")
        return result
    finally:
        result["finished_at"] = now_text()
        write_result(result)
        print(f"result file: {RESULT_PATH}")
        error_files = (
            sorted(ERROR_DIR.glob("err[0-9][0-9]_*.txt"))
            if ERROR_DIR.is_dir()
            else []
        )
        if error_files:
            print(
                f"failure records: total {len(error_files)},"
                f"located at {ERROR_DIR}"
            )


def main() -> int:
    qdrant_spec_path = validate_inputs()
    result = run_one_stage(qdrant_spec_path)
    print(
        "\n=== Cassandra stage-one completed:"
        f"{MODEL_FAMILY}/{int(result.get('repeat_index', 0)):02d}/stage1 ==="
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())