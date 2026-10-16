from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

from openai import OpenAI

# ============================== GPT / OpenAI Fixed Configuration ==============================

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

API_TIMEOUT_SECONDS = int(os.getenv("FORMAL_API_TIMEOUT", "900"))
MAX_OUTPUT_TOKENS = int(os.getenv("FORMAL_MAX_OUTPUT_TOKENS", "50000"))
API_RETRIES = int(os.getenv("FORMAL_API_RETRIES", "3"))
SMOKE_SECONDS = int(os.getenv("TLC_SMOKE_SECONDS", "60"))
SANY_TIMEOUT_SECONDS = int(os.getenv("SANY_TIMEOUT_SECONDS", "120"))
JAVA_BIN = os.getenv("JAVA_BIN", "java")
JAVA_HEAP = os.getenv("TLC_JAVA_HEAP", "2g")
TLC_WORKERS = os.getenv("TLC_WORKERS", "1")
MAX_REPAIR_ROUNDS = int(os.getenv("QDRANT_MAX_REPAIRS", "20"))
MAX_REPAIR_FILES = int(os.getenv("QDRANT_MAX_REPAIR_FILES", "4"))
MAX_ERROR_PROMPT_CHARS = int(os.getenv("QDRANT_MAX_ERROR_PROMPT_CHARS", "40000"))
MAX_RULE_EXCERPT_CHARS = int(os.getenv("QDRANT_MAX_RULE_EXCERPT_CHARS", "18000"))

REQUIRED_FILES = [
    "QCore.tla",
    "QAuth.tla",
    "QWrite.tla",
    "QReplica.tla",
    "QMigrate.tla",
    "QSearch.tla",
    "QFrontierInterface.tla",
    "QIntegrated.tla",
]

SANY_ORDER = [
    "QCore.tla",
    "QAuth.tla",
    "QWrite.tla",
    "QReplica.tla",
    "QMigrate.tla",
    "QSearch.tla",
    "QFrontierInterface.tla",
    "QCfgHelpers.tla",
    "QIntegrated.tla",
]

MILVUS_ORDER = [
    "MCore.tla",
    "MAuth.tla",
    "MWrite.tla",
    "MSync.tla",
    "MMigrate.tla",
    "MQuery.tla",
    "MFrontierInterface.tla",
    "MIntegrated.tla",
]

BUSINESS_PARENT = {
    "QAuth.tla": "QCore",
    "QWrite.tla": "QAuth",
    "QReplica.tla": "QWrite",
    "QMigrate.tla": "QReplica",
    "QSearch.tla": "QMigrate",
    "QFrontierInterface.tla": "QSearch",
}

PREDECESSOR = {
    "QAuth.tla": "QCore.tla",
    "QWrite.tla": "QAuth.tla",
    "QReplica.tla": "QWrite.tla",
    "QMigrate.tla": "QReplica.tla",
    "QSearch.tla": "QMigrate.tla",
    "QFrontierInterface.tla": "QSearch.tla",
    "QIntegrated.tla": "QFrontierInterface.tla",
}

MODULE_REQUIRED_OPERATORS = {
    "QCore.tla": [
        "Operations",
        "ReadConsistencyLevels",
        "WriteStates",
        "MigrateStates",
        "CollectionOfShard",
        "PointsOfShard",
        "ReplicasOfPoint",
        "CoreAssumption",
        "CoreTypeOK",
        "HasMajority",
    ],
    "QAuth.tla": [
        "AuthVars",
        "InitAuth",
        "NextAuth",
        "CanAccess",
        "GrantPermission",
        "RevokePermission",
        "AuthTypeOK",
    ],
    "QWrite.tla": [
        "WriteVars",
        "InitWrite",
        "NextWrite",
        "ReceiveWrite",
        "RejectWrite",
        "ReplicaAck",
        "CommitWrite",
        "SyncReplica",
        "WriteTypeOK",
    ],
    "QReplica.tla": ["ReplicaContains", "Visible", "ReplicaTypeOK"],
    "QMigrate.tla": [
        "MigrateVars",
        "InitMigrate",
        "NextMigrate",
        "StartMigrate",
        "RejectMigrate",
        "AdvanceMigrate",
        "ActivateMigrate",
        "FinishMigrate",
        "MigrationSafe",
        "MigrateTypeOK",
    ],
    "QSearch.tla": [
        "SearchVars",
        "InitSearch",
        "NextSearch",
        "SearchEligibleSet",
        "Search",
        "RejectSearch",
        "SearchTypeOK",
    ],
    "QFrontierInterface.tla": [
        "WriteFrontier",
        "CommitFrontier",
        "ReplicaFrontier",
        "QueryFrontier",
        "MigrateFrontier",
        "SearchFrontier",
        "CommitFrontierSafety",
        "ReplicaFrontierSafety",
        "QueryFrontierSafety",
        "MigrateFrontierSafety",
        "SearchFrontierSafety",
        "SearchResultSafety",
        "FrontierSafety",
    ],
    "QIntegrated.tla": [
        "Init",
        "GlobalVars",
        "IntegratedAuthAction",
        "IntegratedWriteAction",
        "IntegratedMigrateAction",
        "IntegratedSearchAction",
        "Next",
        "Spec",
        "GlobalTypeInvariant",
        "AuthSafety",
        "WalBeforeApply",
        "ReplicaNotAheadOfWAL",
        "MigrateSafety",
    ],
}

MODULE_REQUIRED_VARIABLES = {
    "QAuth.tla": ["permission"],
    "QWrite.tla": ["writeState", "wal", "applied", "ackSet", "replicaHas", "shardData", "lastWrite"],
    "QMigrate.tla": [
        "shardOwner",
        "shardLocation",
        "migrateState",
        "migrateSrc",
        "migrateDst",
        "copiedData",
        "lastMigrate",
    ],
    "QSearch.tla": ["searchResult", "lastSearch"],
}

CORE_CONSTANTS = [
    "Principals",
    "Nodes",
    "Shards",
    "Collections",
    "Points",
    "Replicas",
    "writeConsistencyFactor",
    "replicas",
    "replicaNode",
    "pointShard",
    "pointCollection",
    "shardCollection",
]

CFG_INVARIANTS = [
    "GlobalTypeInvariant",
    "AuthSafety",
    "WalBeforeApply",
    "ReplicaNotAheadOfWAL",
    "FrontierSafety",
    "MigrateSafety",
]

FRONTIER_NAMES = [
    "WriteFrontier",
    "CommitFrontier",
    "ReplicaFrontier",
    "QueryFrontier",
    "MigrateFrontier",
    "SearchFrontier",
    "FrontierSafety",
]

TLC_ERROR_PATTERNS = [
    r"Invariant .* is violated",
    r"The behavior up to this point is",
    r"The following behavior constitutes a counter-example",
    r"Temporal properties were violated",
    r"Deadlock reached",
    r"ConfigFileException",
    r"Parsing or semantic analysis failed",
    r"Semantic errors?",
    r"Successor state is not completely specified",
    r"TLC threw an unexpected exception",
    r"java\.lang\.(?:OutOfMemoryError|StackOverflowError)",
    r"Java ran out of memory",
    r"Error: TLC",
]

FIXED_REPAIR_CONTRACT = r"""
1. Must use the current version on disk as the baseline for minimal-scope incremental repair; full rewrite is not allowed.
2. Must not modify, output, delete, or rename Qdrant.cfg and QCfgHelpers.tla.
3. Must not delete, rename, comment out, or weaken the invariant required by cfg.
4. Must not use invariant == TRUE, Next == FALSE, pure UNCHANGED Next,
   fixed empty query results or permanently non-executable actions to bypass errors.
5. Each action must fully specify the next-state; unchanged variables must be explicitly UNCHANGED.
6. This round only fixes the current errors reported by file extraction, SANY compilation, or TLC;
   do not modify code based on interface contract check results.
7. Only return the complete contents of files actually modified or missing in this round; do not return explanations.
""".strip()


class PipelineError(RuntimeError):
    pass


def find_project_root() -> Path:
    start = Path(__file__).resolve().parent
    for candidate in [start, *start.parents]:
        if (candidate / "docs").is_dir() and (candidate / "milvus").is_dir() and (candidate / "output1").is_dir():
            return candidate
    raise FileNotFoundError("Unable to locate the formalization project root directory containing docs, milvus, and output1.")


ROOT = find_project_root()
DOCS_DIR = ROOT / "docs"
TLA2TOOLS_JAR = DOCS_DIR / "tla2tools.jar"
MILVUS_DIR = ROOT / "milvus"
OUTPUT1_DIR = ROOT / "output1"
MODEL_DIR = OUTPUT1_DIR / MODEL_FAMILY
HELPER_SOURCE_PATH = OUTPUT1_DIR / "QCfgHelpers.tla"

# The following paths are pointed to new 01, 02, 03... directories by configure_new_run_paths() at each startup.
RUN_DIR = MODEL_DIR / "__pending__"
QDRANT_DIR = RUN_DIR / "Qdrant"
CFG_PATH = OUTPUT1_DIR / "Qdrant.cfg"
FRONTIER_PATH = DOCS_DIR / "Frontier_Method.md"
QDRANT_SPEC_PATH = DOCS_DIR / "Qdrant_Specification.md"
INTERFACE_PATH = OUTPUT1_DIR / "Qdrant_Interface_Constraints.md"
RULES_PATH = OUTPUT1_DIR / "TLA_Code_Error_Rules.md"
HELPER_PATH = QDRANT_DIR / "QCfgHelpers.tla"
RESULT_PATH = RUN_DIR / "result.txt"
INTERFACE_LOG_PATH = RUN_DIR / "interface_contract_report.txt"
TLC_LOG_PATH = RUN_DIR / "tlc_output.txt"
ERROR_DIR = RUN_DIR / "error"


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



def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decode_process_output(data: bytes | None) -> str:
    if not data:
        return ""
    for encoding in ("utf-8", "gb18030", sys.getdefaultencoding()):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def validate_fixed_inputs() -> None:
    required = [FRONTIER_PATH, QDRANT_SPEC_PATH, INTERFACE_PATH, RULES_PATH, CFG_PATH, HELPER_SOURCE_PATH, TLA2TOOLS_JAR]
    required.extend(MILVUS_DIR / name for name in MILVUS_ORDER)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("The following input files do not exist: \n" + "\n".join(missing))
    if not MODEL:
        raise EnvironmentError("MODEL must not be empty.")
    if not os.getenv(API_KEY_ENV):
        raise EnvironmentError(
            f"API Key environment variable not set: {API_KEY_ENV}."
        )


def create_next_numeric_run_directory() -> Tuple[Path, int]:
    """
    Create the next 01, 02, 03... directory under output1/gpt/.\n    Each run uses a new number; existing experiment directories are not overwritten.
    """
    global MODEL_DIR
    MODEL_DIR = OUTPUT1_DIR / MODEL_FAMILY
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    existing = [
        int(path.name)
        for path in MODEL_DIR.iterdir()
        if path.is_dir() and re.fullmatch(r"\d{2,}", path.name)
    ]
    next_index = max(existing, default=0) + 1
    while True:
        run_dir = MODEL_DIR / f"{next_index:02d}"
        try:
            run_dir.mkdir(parents=False, exist_ok=False)
            return run_dir, next_index
        except FileExistsError:
            next_index += 1


def configure_run_paths() -> Tuple[Path, int]:
    """Allocate the next independent experiment directory for output1/gpt."""
    global RUN_DIR, QDRANT_DIR, ERROR_DIR
    global HELPER_PATH, RESULT_PATH, INTERFACE_LOG_PATH, TLC_LOG_PATH

    RUN_DIR, repeat_index = create_next_numeric_run_directory()
    QDRANT_DIR = RUN_DIR / "Qdrant"
    HELPER_PATH = QDRANT_DIR / "QCfgHelpers.tla"
    RESULT_PATH = RUN_DIR / "result.txt"
    INTERFACE_LOG_PATH = RUN_DIR / "interface_contract_report.txt"
    TLC_LOG_PATH = RUN_DIR / "tlc_output.txt"
    ERROR_DIR = RUN_DIR / "error"
    return RUN_DIR, repeat_index


def initialize_run_output() -> None:
    """
    Initialize the new directory for this run.

    The only maintained copy of QCfgHelpers.tla is located at:
        output1/QCfgHelpers.tla

    It is automatically copied to the Qdrant subdirectory of this group's current numbered directory for each experiment.
    """
    QDRANT_DIR.mkdir(parents=True, exist_ok=False)
    shutil.copy2(HELPER_SOURCE_PATH, HELPER_PATH)


def build_milvus_bundle() -> str:
    sections: List[str] = []
    for name in MILVUS_ORDER:
        sections.append(
            f"\n===== MILVUS FILE: {name} =====\n{read_text(MILVUS_DIR / name)}\n===== END MILVUS FILE ====="
        )
    return "\n".join(sections)


def build_initial_prompt() -> str:
    return f"""
You need to generate a complete set of Qdrant Frontier-based TLA+ models.

【Experiment workflow】Rule-enhanced cross-model comparison.
Initial generation must reference the complete interface constraints and TLA_Code_Error_Rules.
Subsequent loops only feed back file, SANY, and TLC errors; interface contracts are evaluated only after the loop ends.

【Constraint priority】
1. Qdrant Generation Interface Constraints.md
2. Qdrant Specification.md
3. Frontier General Methods.md
4. Milvus Reference Code
5. General Suggestions for TLA Generation Error-Prone Rules.md

[Fixed Requirements]
- Only output these 8 files: {', '.join(REQUIRED_FILES)}.
- Must not output or modify QCfgHelpers.tla and Qdrant.cfg.
- Strictly maintain: QCore -> QAuth -> QWrite -> QReplica -> QMigrate
  -> QSearch -> QFrontierInterface -> QIntegrated。
- QSearch defines SearchEligibleSet, must not forward-reference any Frontier operator.
- QFrontierInterface EXTENDS QSearch, only defines Frontier and safety properties, no variables, no actions.
- Successful Search must fully return SearchEligibleSet, must not use an arbitrary subset.
- Each action fully specifies next-state, unmodified variables explicitly UNCHANGED.
- Prohibit tautological invariant, Next == FALSE, fixed empty Frontier/query results, and other degenerate formulations.

[Strict Output Format]
Do not use Markdown fences. For each file use:
===== FILE: filename =====
<complete file content>
===== END FILE =====

================ Frontier General Methods.md ================
{read_text(FRONTIER_PATH)}

================ Qdrant Specification.md ================
{read_text(QDRANT_SPEC_PATH)}

================ Qdrant Generation Interface Constraints.md ================
{read_text(INTERFACE_PATH)}

================ TLA Generation Error-Prone Rules.md ================
{read_text(RULES_PATH)}

================ Fixed Qdrant.cfg (read-only) ================
{read_text(CFG_PATH)}

================ Fixed QCfgHelpers.tla (read-only) ================
{read_text(HELPER_PATH)}

================ Milvus Reference Code ================
{build_milvus_bundle()}
""".strip()



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
    system_prompt: str,
) -> Tuple[str, Dict[str, int]]:
    last_error: Exception | None = None

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


def strip_outer_fence(text: str) -> str:
    value = text.strip()
    value = re.sub(r"^```(?:tla\+?|text)?\s*\n", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\n```\s*$", "", value)
    return value.strip() + "\n"


def extract_tla_files(response_text: str) -> Tuple[Dict[str, str], List[str]]:
    files: Dict[str, str] = {}
    unexpected: List[str] = []
    marker = re.compile(r"(?im)^\s*(?:={3,}\s*)?FILE:\s*([A-Za-z0-9_]+\.tla)\s*(?:={3,})?\s*$")
    matches = list(marker.finditer(response_text))
    for index, match in enumerate(matches):
        name = match.group(1)
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(response_text)
        block = response_text[start:end]
        block = re.split(
            r"(?im)^\s*(?:={3,}\s*)?END FILE(?:\s*:\s*[^\n]+)?\s*(?:={3,})?\s*$",
            block,
            maxsplit=1,
        )[0]
        if name in REQUIRED_FILES:
            files[name] = strip_outer_fence(block)
        else:
            unexpected.append(name)
    if not files:
        module_pattern = re.compile(r"(?ms)^-{4,}\s*MODULE\s+(Q[A-Za-z0-9_]+)\s*-{4,}\s*\n.*?^={4,}\s*$")
        for match in module_pattern.finditer(response_text):
            name = f"{match.group(1)}.tla"
            if name in REQUIRED_FILES:
                files[name] = match.group(0).strip() + "\n"
            else:
                unexpected.append(name)
    return files, sorted(set(unexpected))


def write_generated_files(files: Dict[str, str]) -> None:
    for name, content in files.items():
        if name in REQUIRED_FILES:
            write_text(QDRANT_DIR / name, content)


def remove_tla_comments(code: str) -> str:
    without_blocks = re.sub(r"\(\*.*?\*\)", "", code, flags=re.DOTALL)
    without_lines = re.sub(r"(?m)^\s*\\\*.*$", "", without_blocks)
    return without_lines


def operator_defined(code: str, name: str) -> bool:
    return bool(re.search(rf"(?m)^\s*{re.escape(name)}\s*(?:\([^\n]*\))?\s*==", code))


def declared_names(code: str, keyword: str) -> set[str]:
    names: set[str] = set()
    pattern = re.compile(
        rf"(?ms)^\s*{keyword}\b(.*?)(?=^\s*(?:CONSTANTS?|VARIABLES?|ASSUME|RECURSIVE|LOCAL|[A-Za-z_][A-Za-z0-9_]*\s*(?:\([^\n]*\))?\s*==|={4,}))"
    )
    for match in pattern.finditer(code):
        block = re.sub(r"\\\*.*", "", match.group(1))
        names.update(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", block))
    return names


def extends_block(code: str) -> str:
    match = re.search(
        r"(?ms)^\s*EXTENDS\b(.*?)(?=^\s*(?:CONSTANTS?|VARIABLES?|ASSUME|RECURSIVE|LOCAL|[A-Za-z_][A-Za-z0-9_]*\s*(?:\([^\n]*\))?\s*==|={4,}))",
        code,
    )
    return match.group(1) if match else ""


def basic_file_errors() -> List[str]:
    errors: List[str] = []
    allowed = set(REQUIRED_FILES + ["QCfgHelpers.tla"])
    actual_tla = {path.name for path in QDRANT_DIR.glob("*.tla")}
    for name in REQUIRED_FILES:
        path = QDRANT_DIR / name
        if not path.is_file():
            errors.append(f"Missing file: {name}")
            continue
        code = read_text(path)
        if not code.strip():
            errors.append(f"Empty file: {name}")
            continue
        if "```" in code:
            errors.append(f"Residual Markdown fence: {name}")
        expected = Path(name).stem
        header = re.search(r"(?m)^-{4,}\s*MODULE\s+([A-Za-z0-9_]+)\s*-{4,}\s*$", code)
        if not header:
            errors.append(f"Missing standard MODULE header: {name}")
        elif header.group(1) != expected:
            errors.append(f"MODULE name error: {name} -> {header.group(1)}")
        if not re.search(r"(?m)^={4,}\s*$", code.rstrip()):
            errors.append(f"Missing ==== at end of module: {name}")
    unexpected = sorted(actual_tla - allowed)
    if unexpected:
        errors.append("Additional TLA files: " + ", ".join(unexpected))
    for path in QDRANT_DIR.iterdir():
        if path.is_file() and path.suffix.lower() != ".tla":
            errors.append(f"Non-TLA file found in Qdrant directory: {path.name}")
    return errors


def check_interface_contract(helper_hash: str) -> Tuple[bool, str]:
    """
    Check the fixed generation interface after this generation and execution process ends.

    Here, only the hard contracts in the Qdrant generation interface constraints that can be mechanically verified are checked,
    it does not prescribe which equivalent form must be used inside operators, nor does it judge business semantic quality.
    """
    errors: List[str] = []

    # Fixed core modules and read-only helper.
    for file_name in REQUIRED_FILES:
        if not (QDRANT_DIR / file_name).is_file():
            errors.append(f"Missing module required by interface: {file_name}")

    if not HELPER_PATH.is_file():
        errors.append("Fixed QCfgHelpers.tla is missing.")
    elif sha256_file(HELPER_PATH) != helper_hash:
        errors.append("Hash of fixed QCfgHelpers.tla changed.")

    clean_codes: Dict[str, str] = {}
    for file_name in REQUIRED_FILES:
        path = QDRANT_DIR / file_name
        if path.is_file():
            clean_codes[file_name] = remove_tla_comments(read_text(path))

    # Fixed module dependency chain.
    for file_name, parent in BUSINESS_PARENT.items():
        code = clean_codes.get(file_name, "")
        if code and not re.search(
            rf"\b{re.escape(parent)}\b",
            extends_block(code),
        ):
            errors.append(f"{file_name} must EXTENDS {parent}.")

    integrated_code = clean_codes.get("QIntegrated.tla", "")
    integrated_extends = extends_block(integrated_code)
    for parent in ("QFrontierInterface", "QCfgHelpers"):
        if integrated_code and not re.search(
            rf"\b{re.escape(parent)}\b",
            integrated_extends,
        ):
            errors.append(f"QIntegrated.tla must EXTENDS {parent}.")

    # Constants, variables, and operator names specified by the interface document.
    core_constants = declared_names(
        clean_codes.get("QCore.tla", ""),
        "CONSTANTS?",
    )
    for constant in CORE_CONSTANTS:
        if constant not in core_constants:
            errors.append(f"QCore.tla missing interface constant: {constant}")

    for file_name, required_vars in MODULE_REQUIRED_VARIABLES.items():
        variables = declared_names(
            clean_codes.get(file_name, ""),
            "VARIABLES?",
        )
        for variable in required_vars:
            if variable not in variables:
                errors.append(f"{file_name} missing interface variable: {variable}")

    for file_name, operators in MODULE_REQUIRED_OPERATORS.items():
        code = clean_codes.get(file_name, "")
        for operator in operators:
            if not code or not operator_defined(code, operator):
                errors.append(f"{file_name} missing interface operator: {operator}")

    # Frontier interface module must remain stateless.
    frontier_code = clean_codes.get("QFrontierInterface.tla", "")
    if re.search(r"(?m)^\s*VARIABLES?\b", frontier_code):
        errors.append("QFrontierInterface.tla must not declare state variables.")
    if re.search(r"\b[A-Za-z_][A-Za-z0-9_]*'", frontier_code):
        errors.append("QFrontierInterface.tla must not update state variables.")
    for forbidden_op in (
        "Init",
        "Next",
        "ReceiveWrite",
        "Search",
        "StartMigrate",
        "CommitWrite",
    ):
        if operator_defined(frontier_code, forbidden_op):
            errors.append(
                "QFrontierInterface.tla must not define state or business actions:"
                + forbidden_op
            )

    # Invariants referenced by the fixed cfg must exist.
    all_code = "\n".join(clean_codes.values())
    for invariant in CFG_INVARIANTS:
        if not operator_defined(all_code, invariant):
            errors.append(f"invariant referenced by Qdrant.cfg does not exist: {invariant}")

    # Direct degenerate forms explicitly prohibited by the interface documentation.
    key_invariants = (
        "GlobalTypeInvariant",
        "AuthSafety",
        "WalBeforeApply",
        "ReplicaNotAheadOfWAL",
        "FrontierSafety",
        "MigrateSafety",
    )
    for file_name, code in clean_codes.items():
        if re.search(
            r"(?m)^\s*Next\s*==\s*(?:FALSE|TRUE)\s*$",
            code,
        ):
            errors.append(f"{file_name} degrades Next to a constant.")
        for invariant in key_invariants:
            if re.search(
                rf"(?m)^\s*{re.escape(invariant)}"
                rf"(?:\s*\([^\n]*\))?\s*==\s*TRUE\s*$",
                code,
            ):
                errors.append(
                    f"{file_name} degrades critical invariant {invariant} to TRUE."
                )
        if re.search(
            r"(?m)^\s*(?:WriteFrontier|CommitFrontier|"
            r"ReplicaFrontier|QueryFrontier|MigrateFrontier|"
            r"SearchFrontier)(?:\s*\([^\n]*\))?\s*==\s*\{\}\s*$",
            code,
        ):
            errors.append(f"{file_name} fixes critical Frontier to the empty set.")
        if re.search(r"searchResult'\s*=\s*\{\}", code):
            errors.append(f"{file_name} fixes successful query results to the empty set.")

    # cfg model value must not be hardcoded in business modules.
    model_values = (
        "P1", "P2", "N1", "N2", "N3", "S1", "C1",
        "PT1", "PT2", "R1", "R2", "R3",
    )
    for model_value in model_values:
        for file_name, code in clean_codes.items():
            if re.search(rf"\b{model_value}\b", code):
                errors.append(
                    f"{file_name} hardcoded cfg model value: {model_value}"
                )
                break

    if errors:
        report = "INTERFACE CONTRACT CHECK: FAIL\n"
        report += "\n".join(
            f"{index + 1}. {message}"
            for index, message in enumerate(errors)
        ) + "\n"
    else:
        report = (
            "INTERFACE CONTRACT CHECK: PASS\n"
            "Confirmed fixed modules, dependencies, interface names, read-only helpers, cfg invariant "
            "and explicit anti-degradation clauses; unique implementation form or business semantic correctness was not checked.\n"
        )

    if errors:
        write_text(INTERFACE_LOG_PATH, report)
    elif INTERFACE_LOG_PATH.exists():
        INTERFACE_LOG_PATH.unlink()
    return not errors, report

def new_validation_status() -> Dict[str, object]:
    """Create independent state for each check item, do not generate overall field."""
    return {
        "file_extract_result": "not_run",
        "file_completeness_result": "not_run",
        "sany_result": "not_run",
        "tlc_smoke_result": "not_run",
        "tlc_smoke_end": "not_run",
        "interface_contract_result": "not_run",
        "manual_logic_result": "pending",
    }

def new_validation_reasons() -> Dict[str, object]:
    """Save independent, concise failure reasons for each check item."""
    return {
        "file_extract_reason": "none",
        "file_completeness_reason": "none",
        "sany_reason": "none",
        "tlc_smoke_reason": "none",
        "interface_contract_reason": "none",
        "process_reason": "none",
    }

def collect_failed_checks(
    status: Dict[str, object],
    process_reason: str = "none",
) -> str:
    failed: List[str] = []
    checks = (
        ("file_extract", "file_extract_result"),
        ("file_completeness", "file_completeness_result"),
        ("sany", "sany_result"),
        ("tlc", "tlc_smoke_result"),
        ("interface_contract", "interface_contract_result"),
    )
    for check_name, field_name in checks:
        if status.get(field_name) == "fail":
            failed.append(check_name)

    if process_reason != "none":
        failed.append("process")

    return ",".join(failed) if failed else "none"

def apply_validation_outcome(
    result: Dict[str, object],
    status: Dict[str, object],
    reasons: Dict[str, object],
) -> None:
    """Write the latest check state of this round into the final result."""
    result.update(status)
    result.update(reasons)
    result["failed_checks"] = collect_failed_checks(
        status,
        str(reasons.get("process_reason", "none")),
    )


def apply_extraction_failure(result: Dict[str, object], details: str) -> None:
    """Record the case where the initial API response failed to form the specified file set."""
    status = new_validation_status()
    reasons = new_validation_reasons()
    status["file_extract_result"] = "fail"
    status["file_completeness_result"] = "fail"

    concise = concise_failure_reason("extract", details)
    reasons["file_extract_reason"] = concise
    reasons["file_completeness_reason"] = "did not form a complete and unique specified TLA+ file set"
    apply_validation_outcome(result, status, reasons)


def apply_process_failure(
    result: Dict[str, object],
    stage: str,
    details: str,
) -> None:
    """Record API, repair call, or script pipeline exceptions without overwriting existing check results."""
    reason = concise_failure_reason(stage, details)
    result["process_reason"] = reason
    status = {
        key: result.get(key, value)
        for key, value in new_validation_status().items()
    }
    result["failed_checks"] = collect_failed_checks(status, reason)


def evaluate_interface_contract(
    result: Dict[str, object],
    helper_hash: str,
) -> Tuple[bool, str]:
    """
    Execute interface contract checks on the final code on the current disk and write back the results.

    This check can be executed after SANY/TLC succeeds or fails; therefore, even if the run never passes,
    It can still be seen whether the final code complies with the fixed generation interface.
    """
    ok, report = check_interface_contract(helper_hash)
    result["interface_contract_result"] = "pass" if ok else "fail"
    result["interface_contract_reason"] = (
        "none"
        if ok
        else concise_failure_reason("interface_contract", report)
    )
    status = {
        key: result.get(key, value)
        for key, value in new_validation_status().items()
    }
    result["failed_checks"] = collect_failed_checks(
        status,
        str(result.get("process_reason", "none")),
    )
    return ok, report


def validate_execution(
    jar_path: Path,
) -> Tuple[Dict[str, object], Dict[str, object], str, str]:
    """
    The automatic execution phase only handles: file -> SANY -> TLC.

    Interface contracts are not mixed with SANY/TLC errors; they are checked separately after the execution phase ends.
    """
    status = new_validation_status()
    reasons = new_validation_reasons()

    required_files_exist = all(
        (QDRANT_DIR / name).is_file() for name in REQUIRED_FILES
    )
    status["file_extract_result"] = (
        "pass" if required_files_exist else "fail"
    )
    if not required_files_exist:
        missing = [
            name
            for name in REQUIRED_FILES
            if not (QDRANT_DIR / name).is_file()
        ]
        reasons["file_extract_reason"] = (
            "Missing specified files:" + ", ".join(missing)
        )

    file_errors = basic_file_errors()
    status["file_completeness_result"] = (
        "pass" if not file_errors else "fail"
    )
    if file_errors:
        file_details = "\n".join(file_errors)
        reasons["file_completeness_reason"] = concise_failure_reason(
            "file",
            file_details,
        )
    else:
        file_details = ""

    if not required_files_exist or file_errors:
        details = file_details or str(reasons["file_extract_reason"])
        return status, reasons, "file", details

    sany_ok, sany_output = run_sany(jar_path)
    status["sany_result"] = "pass" if sany_ok else "fail"
    if not sany_ok:
        reasons["sany_reason"] = concise_failure_reason(
            "sany",
            sany_output,
        )
        return status, reasons, "sany", sany_output

    tlc_ok, tlc_output, timed_out = run_tlc_smoke(jar_path)
    status["tlc_smoke_result"] = "pass" if tlc_ok else "fail"
    status["tlc_smoke_end"] = (
        "timeout" if timed_out else "completed"
    )
    if not tlc_ok:
        reasons["tlc_smoke_reason"] = concise_failure_reason(
            "tlc",
            tlc_output,
        )
        return status, reasons, "tlc", tlc_output

    return status, reasons, "execution_success", tlc_output

def run_sany(jar_path: Path) -> Tuple[bool, str]:
    sections: List[str] = []
    success = True
    for name in SANY_ORDER:
        path = QDRANT_DIR / name
        if not path.is_file():
            sections.append(f"===== {name} =====\nFile does not exist.")
            success = False
            break
        cmd = [JAVA_BIN, f"-Xmx{JAVA_HEAP}", "-cp", str(jar_path), "tla2sany.SANY", name]
        try:
            completed = subprocess.run(
                cmd,
                cwd=QDRANT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=SANY_TIMEOUT_SECONDS,
                check=False,
            )
            output = decode_process_output(completed.stdout)
            sections.append(
                f"===== COMMAND =====\n{' '.join(cmd)}\n"
                f"===== MODULE: {name}; RETURN CODE: {completed.returncode} =====\n{output}"
            )
            lowered = output.lower()
            if completed.returncode != 0 or "parsing or semantic analysis failed" in lowered or "semantic errors" in lowered:
                success = False
                break
        except subprocess.TimeoutExpired as exc:
            sections.append(
                f"===== MODULE: {name}; TIMEOUT =====\n"
                + decode_process_output(exc.stdout)
                + decode_process_output(exc.stderr)
            )
            success = False
            break
    full = "\n\n".join(sections)
    return success, full


def contains_tlc_error(output: str) -> bool:
    return any(re.search(pattern, output, flags=re.IGNORECASE | re.DOTALL) for pattern in TLC_ERROR_PATTERNS)


def run_tlc_smoke(jar_path: Path) -> Tuple[bool, str, bool]:
    cmd = [
        JAVA_BIN,
        f"-Xmx{JAVA_HEAP}",
        "-cp",
        str(jar_path),
        "tlc2.TLC",
        "-workers",
        str(TLC_WORKERS),
        "-config",
        str(CFG_PATH.resolve()),
        "QIntegrated.tla",
    ]
    process = subprocess.Popen(
        cmd,
        cwd=QDRANT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    timed_out = False
    try:
        stdout, _ = process.communicate(timeout=SMOKE_SECONDS)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        stdout, _ = process.communicate()

    output = (
        f"===== COMMAND =====\n{' '.join(cmd)}\n"
        f"===== RETURN CODE: {process.returncode}; "
        f"TIMED OUT: {timed_out} =====\n"
        + decode_process_output(stdout)
    )
    has_error = contains_tlc_error(output)
    ok = (
        (not has_error)
        if timed_out
        else (process.returncode == 0 and not has_error)
    )

    # TLC failure output goes into error.log; only when TLC passes,
    # is the complete output of this successful execution saved separately for later inspection of state statistics.
    if ok:
        write_text(TLC_LOG_PATH, output)
    elif TLC_LOG_PATH.exists():
        # The current experiment directory is usually newly created; this is used to avoid unexpectedly retaining old successful results.
        TLC_LOG_PATH.unlink()

    return ok, output, timed_out

def compact_error(text: str) -> str:
    if len(text) <= MAX_ERROR_PROMPT_CHARS:
        return text
    head = MAX_ERROR_PROMPT_CHARS // 3
    tail = MAX_ERROR_PROMPT_CHARS - head
    return text[:head] + "\n\n... intermediate content omitted to save API input ...\n\n" + text[-tail:]


def split_rule_sections(rules_text: str) -> List[Tuple[str, str]]:
    matches = list(re.finditer(r"(?m)^##\s+.*$", rules_text))
    sections: List[Tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = (
            matches[index + 1].start()
            if index + 1 < len(matches)
            else len(rules_text)
        )
        heading = match.group(0).strip()
        sections.append((heading, rules_text[match.start():end].strip()))
    return sections


def select_rule_excerpt(stage: str, error_text: str) -> str:
    """
    The repair phase only sends general TLA+/cfg/next-state rules.
    Fixed module interfaces, QSearch/Frontier layering, and business interface clauses are not sent repeatedly.
    """
    sections = split_rule_sections(read_text(RULES_PATH))
    generic_heading_keywords = (
        "character", "syntax", "extends", "operator", "cfg", "helper",
        "function", "set", "record", "let", "scope", "variable", "init",
        "typeok", "next-state", "next、spec", "next", "spec",
        "invariant", "error phase", "incremental repair", "repair hint",
    )
    excluded_heading_keywords = (
        "fixed files", "forced order", "qsearch", "qfrontierinterface",
        "frontier common", "permission", "write", "migration", "static pre-check",
    )
    chosen: List[str] = []
    for heading, body in sections:
        lower = heading.lower()
        if any(word in lower for word in excluded_heading_keywords):
            continue
        if any(word in lower for word in generic_heading_keywords):
            chosen.append(body)

    excerpt = "\n\n".join(chosen)
    if not excerpt:
        excerpt = read_text(RULES_PATH)[:MAX_RULE_EXCERPT_CHARS]
    if len(excerpt) > MAX_RULE_EXCERPT_CHARS:
        excerpt = (
            excerpt[:MAX_RULE_EXCERPT_CHARS]
            + "\n\n(The general rule fragment has been truncated according to the input limit.)"
        )
    return excerpt


def find_defining_file(operator_name: str) -> str | None:
    pattern = re.compile(rf"(?m)^\s*{re.escape(operator_name)}\s*(?:\([^\n]*\))?\s*==")
    for name in REQUIRED_FILES:
        path = QDRANT_DIR / name
        if path.is_file() and pattern.search(read_text(path)):
            return name
    return None


def select_relevant_files(stage: str, error_text: str) -> List[str]:
    selected: List[str] = []

    def add(name: str) -> None:
        if name in REQUIRED_FILES and (QDRANT_DIR / name).is_file() and name not in selected:
            selected.append(name)

    for name in REQUIRED_FILES:
        if re.search(rf"\b{re.escape(name)}\b", error_text, flags=re.IGNORECASE):
            add(name)

    keyword_map = [
        (r"Auth|permission|CanAccess|Grant|Revoke", ["QAuth.tla"]),
        (r"WAL|writeState|ackSet|CommitWrite|ReceiveWrite|lastWrite|SyncReplica", ["QWrite.tla"]),
        (r"Replica|replicaHas|Visible|Majority", ["QReplica.tla", "QWrite.tla"]),
        (r"Migrate|Migration|copiedData|shardOwner|shardLocation", ["QMigrate.tla"]),
        (r"Search|searchResult|lastSearch|SearchEligibleSet", ["QSearch.tla"]),
        (r"Frontier", ["QFrontierInterface.tla", "QSearch.tla"]),
        (r"Init|Next|Spec|GlobalVars|GlobalTypeInvariant|cfg|ConfigFile", ["QIntegrated.tla"]),
    ]
    for pattern, names in keyword_map:
        if re.search(pattern, error_text, flags=re.IGNORECASE):
            for name in names:
                add(name)

    for invariant in CFG_INVARIANTS:
        if invariant.lower() in error_text.lower():
            owner = find_defining_file(invariant)
            if owner:
                add(owner)

    if stage in {"tlc", "sany"}:
        add("QIntegrated.tla")
    if not selected:
        add("QIntegrated.tla")
        add("QFrontierInterface.tla")
    for name in list(selected):
        predecessor = PREDECESSOR.get(name)
        if predecessor:
            add(predecessor)
    return [name for name in REQUIRED_FILES if name in selected][:6]


def build_current_code_bundle(names: Sequence[str]) -> str:
    sections: List[str] = []
    for name in names:
        path = QDRANT_DIR / name
        if path.is_file():
            sections.append(f"===== CURRENT FILE: {name} =====\n{read_text(path)}\n===== END CURRENT FILE =====")
    return "\n\n".join(sections) or "(Currently there are no readable generated files.)"


def build_repair_prompt(
    stage: str,
    error_text: str,
    relevant_files: Sequence[str],
) -> str:
    missing = [
        name for name in REQUIRED_FILES
        if not (QDRANT_DIR / name).is_file()
    ]
    return f"""
Please complete one minimal-scope incremental repair based on the current failure information and the existing version on disk.

[The failure phase handled only in this round]
{stage}

[Missing files]
{', '.join(missing) if missing else 'none'}

[General TLA+ error-prone rules related to the current error]
{select_rule_excerpt(stage, error_text)}

[Fixed repair constraints]
{FIXED_REPAIR_CONTRACT}

[Current error]
{compact_error(error_text)}

[Current related code]
{build_current_code_bundle(relevant_files)}

[Output format]
Return only the files actually modified or supplemented in this round, at most {MAX_REPAIR_FILES};
Do not use Markdown fences:
===== FILE: Qxxx.tla =====
<Complete modified file content>
===== END FILE =====
""".strip()


def normalize_error_stage(stage: str) -> str:
    aliases = {
        "extract": "extract",
        "file": "file",
        "sany": "sany",
        "tlc": "tlc",
        "execution_repair_error": "repair",
        "repair_error": "repair",
        "api_or_repair": "api",
        "pipeline": "pipeline",
    }
    normalized = aliases.get(stage.strip().lower(), stage.strip().lower())
    normalized = re.sub(r"[^a-z0-9_]+", "_", normalized).strip("_")
    return normalized or "unknown"


def save_error(counter: int, stage: str, details: str) -> Path:
    stage_name = normalize_error_stage(stage)
    error_path = ERROR_DIR / f"err{counter:02d}_{stage_name}.txt"
    content = (
        f"time={now_text()}\n"
        f"stage={stage}\n"
        f"model={MODEL}\n"
        f"error_index={counter}\n"
        f"\n===== DETAILS =====\n"
        f"{details}\n"
    )
    write_text(error_path, content)
    return error_path

def add_usage(total: Dict[str, int], usage: Dict[str, int]) -> None:
    for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
        total[key] = total.get(key, 0) + usage.get(key, 0)


def concise_failure_reason(stage: str, details: str) -> str:
    """Compress the complete error output into a one-line summary suitable for result.txt."""
    text = str(details or "").strip()
    if not text:
        return "No error details provided"

    if stage in {"extract", "file"}:
        return "；".join(line.strip() for line in text.splitlines() if line.strip())[:500]

    if stage == "interface_contract":
        numbered = re.findall(r"(?m)^\s*\d+\.\s*(.+)$", text)
        if numbered:
            preview = "；".join(item.strip() for item in numbered[:3])
            if len(numbered) > 3:
                preview += f"; and {len(numbered) - 3} more items"
            return f"Interface contract failed: {preview}"
        return "Interface contract failed, see interface_contract_report.txt for details"

    if stage == "sany":
        failed_module = ""
        module_blocks = re.findall(
            r"===== MODULE:\s*([^;\n]+);\s*RETURN CODE:\s*([^\s=]+)\s*=====",
            text,
            flags=re.IGNORECASE,
        )
        for module_name, return_code in module_blocks:
            if return_code not in {"0", "0.0"}:
                failed_module = module_name.strip()
        if not failed_module and module_blocks:
            failed_module = module_blocks[-1][0].strip()
        if not failed_module:
            failed_module = "Unknown module"

        location = re.search(
            r"line\s+(\d+),\s*column\s+(\d+)",
            text,
            flags=re.IGNORECASE,
        )
        encountered = re.search(
            r'Encountered\s+"([^"]*)".*?token\s+"([^"]*)"',
            text,
            flags=re.IGNORECASE | re.DOTALL,
        )

        if location and encountered:
            line_no, column_no = location.groups()
            symbol, token = encountered.groups()
            symbol_name = {
                ",": "comma",
                ":": "colon",
                ")": "right parenthesis",
                "(": "left parenthesis",
            }.get(symbol, f"symbol {symbol}")
            return (
                f"{failed_module} SANY parse failed: line {line_no}, column {column_no},"
                f"illegal {symbol_name} near {token}"
            )

        if location:
            line_no, column_no = location.groups()
            return f"{failed_module} SANY check failed: line {line_no}, column {column_no}"

        important_patterns = [
            r"Unknown operator[^\n]*",
            r"Multiply-defined symbol[^\n]*",
            r"Successor state is not completely specified[^\n]*",
            r"Semantic error[^\n]*",
            r"\*\*\*Parse Error\*\*\*[^\n]*",
        ]
        for pattern in important_patterns:
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if match:
                return f"{failed_module} SANY check failed: {match.group(0).strip()[:350]}"
        return f"{failed_module} failed SANY check"

    if stage == "tlc":
        invariant = re.search(
            r"Invariant\s+([A-Za-z_][A-Za-z0-9_]*)\s+is violated",
            text,
            flags=re.IGNORECASE,
        )
        if invariant:
            return f"TLC one-minute test failed: invariant {invariant.group(1)} violated"

        for pattern, message in (
            (r"Deadlock reached", "Deadlock detected"),
            (r"ConfigFileException[^\n]*", None),
            (r"Successor state is not completely specified[^\n]*", None),
            (r"Java ran out of memory", "Java out of memory"),
            (r"OutOfMemoryError", "Java out of memory"),
        ):
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if match:
                return f"TLC one-minute test failed: {message or match.group(0).strip()[:350]}"
        return "TLC one-minute test did not pass, see corresponding errNN_tlc.txt"

    if stage == "api_or_repair":
        return f"API or incremental repair failed: {text.splitlines()[0][:450]}"

    if stage == "pipeline":
        return f"Script pipeline exception: {text.splitlines()[0][:450]}"

    return text.splitlines()[0][:500]

def print_validation_summary(result: Dict[str, object]) -> None:
    """Display each independent result in the terminal, without merging into overall."""
    status_text = {
        "pass": "passed",
        "fail": "failed",
        "not_run": "not executed",
        "pending": "pending manual check",
    }
    items = (
        ("File extraction", "file_extract_result"),
        ("File completeness", "file_completeness_result"),
        ("SANY compilation", "sany_result"),
        ("TLC one-minute test", "tlc_smoke_result"),
        ("Interface contract check", "interface_contract_result"),
        ("Manual logic check", "manual_logic_result"),
    )

    print("\nCheck results summary:")
    for label, field in items:
        value = str(result.get(field, "not_run"))
        print(f"  {label}：{status_text.get(value, value)}")

    if str(result.get("tlc_smoke_result", "not_run")) != "not_run":
        end_value = str(result.get("tlc_smoke_end", "not_run"))
        end_text = {
            "timeout": "terminated after one minute",
            "completed": "TLC ended on its own",
            "not_run": "not executed",
        }.get(end_value, end_value)
        print(f"  TLC end method: {end_text}")

    failed_checks = str(result.get("failed_checks", "none"))
    print(f"  Failed items: {'none' if failed_checks == 'none' else failed_checks}")

    reason_fields = (
        ("File extraction reason", "file_extract_reason"),
        ("File completeness reason", "file_completeness_reason"),
        ("SANY reason", "sany_reason"),
        ("TLC reason", "tlc_smoke_reason"),
        ("interface contract reason", "interface_contract_reason"),
        ("process exception", "process_reason"),
    )
    for label, field in reason_fields:
        reason = str(result.get(field, "none"))
        if reason != "none":
            print(f"  {label}：{reason}")

def write_result(values: Dict[str, object]) -> None:
    write_text(RESULT_PATH, "\n".join(f"{k}={v}" for k, v in values.items()) + "\n")




def run_one_experiment() -> Dict[str, object]:
    run_dir, repeat_index = configure_run_paths()
    initialize_run_output()
    print(
        f"\n=== Qdrant GPT/{repeat_index:02d}："
        "Rule-enhanced generation + file/SANY/TLC iterative repair + final interface evaluation ==="
    )
    print(f"Experiment directory: {run_dir}")
    print(f"Actual model: {MODEL_FAMILY} -> {PROVIDER}/{MODEL}")

    helper_original = read_text(HELPER_PATH)
    helper_hash = sha256_file(HELPER_PATH)
    client = create_client()
    jar_path = TLA2TOOLS_JAR

    usage_total = {
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
    }
    api_calls = 0
    api_retry_failures = 0
    repair_rounds = 0
    error_counter = 0
    current_stage = "initial"
    current_error = ""
    execution_completed = False
    stop_reason = "none"

    result: Dict[str, object] = {
        "model_family": MODEL_FAMILY,
        "provider": PROVIDER,
        "model": MODEL,
        "base_url": BASE_URL,
        "repeat_index": f"{repeat_index:02d}",
        "started_at": now_text(),
        "check_scheme": "grouped_error_directory_with_success_tlc_v4",
        "interface_contract_usage": "final_evaluation_only_no_feedback",
        "max_repair_rounds": MAX_REPAIR_ROUNDS,
        "api_calls": 0,
        "repair_rounds": 0,
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
        "helper_sha256": helper_hash,
        "interface_sha256": sha256_file(INTERFACE_PATH),
        "qdrant_spec_sha256": sha256_file(QDRANT_SPEC_PATH),
        "frontier_sha256": sha256_file(FRONTIER_PATH),
        "rules_sha256": sha256_file(RULES_PATH),
        "cfg_sha256": sha256_file(CFG_PATH),
        **new_validation_status(),
        "failed_checks": "none",
        **new_validation_reasons(),
    }

    try:
        print("Initial full generation in progress...")
        response_text, usage = call_model(
            client,
            build_initial_prompt(),
            "You are a strict TLA+ formal modeling and incremental repair engineer."
            "Initial generation follows the input interface; during repair, handle only current file, SANY or TLC errors.",
        )
        api_calls += 1
        add_usage(usage_total, usage)
        files, unexpected = extract_tla_files(response_text)
        write_generated_files(files)
        missing = sorted(set(REQUIRED_FILES) - set(files))

        if unexpected or missing:
            parts: List[str] = []
            if missing:
                parts.append("Missing extractable files: " + ", ".join(missing))
            if unexpected:
                parts.append(
                    "Initial response contains forbidden additional files:"
                    + ", ".join(unexpected)
                )
            current_stage = "extract"
            current_error = "\n".join(parts)
            apply_extraction_failure(result, current_error)
        else:
            status, reasons, current_stage, current_error = (
                validate_execution(jar_path)
            )
            apply_validation_outcome(result, status, reasons)
            execution_completed = current_stage == "execution_success"

        if not execution_completed:
            error_counter += 1
            save_error(error_counter, current_stage, current_error)

        while (
            not execution_completed
            and repair_rounds < MAX_REPAIR_ROUNDS
        ):
            repair_rounds += 1
            relevant_files = select_relevant_files(
                current_stage,
                current_error,
            )
            print(
                f"\n--- {MODEL_FAMILY}/{repeat_index:02d} repair "
                f"{repair_rounds}/{MAX_REPAIR_ROUNDS} ---\n"
                f"Current issue: {current_stage}\n"
                f"Files sent:"
                f"{', '.join(relevant_files) if relevant_files else 'none'}"
            )

            try:
                repair_response, usage = call_model(
                    client,
                    build_repair_prompt(
                        current_stage,
                        current_error,
                        relevant_files,
                    ),
                    "You are a strict TLA+ incremental repair engineer."
                    "Only repair current file extraction, SANY or TLC errors; do not perform interface contract repair.",
                )
                api_calls += 1
                add_usage(usage_total, usage)
                returned_files, unexpected = extract_tla_files(
                    repair_response
                )
                if unexpected:
                    raise PipelineError(
                        "Repair response contains forbidden files:"
                        + ", ".join(unexpected)
                    )
                if not returned_files:
                    raise PipelineError(
                        "No valid TLA files were extracted from the repair response."
                    )
                if len(returned_files) > MAX_REPAIR_FILES:
                    raise PipelineError(
                        f"Repair response returned {len(returned_files)} files,"
                        f"Exceeds the upper limit {MAX_REPAIR_FILES}."
                    )
                write_generated_files(returned_files)
                if sha256_file(HELPER_PATH) != helper_hash:
                    write_text(HELPER_PATH, helper_original)
                    raise PipelineError(
                        "Fixed QCfgHelpers.tla was modified and automatically restored."
                    )

                status, reasons, current_stage, current_error = (
                    validate_execution(jar_path)
                )
                apply_validation_outcome(result, status, reasons)
                execution_completed = (
                    current_stage == "execution_success"
                )
            except Exception as exc:
                current_stage = "api_or_repair"
                current_error = str(exc)
                apply_process_failure(
                    result,
                    "api_or_repair",
                    current_error,
                )

            if not execution_completed:
                error_counter += 1
                save_error(error_counter, current_stage, current_error)

        if execution_completed:
            stop_reason = "execution_success"
            print(
                f"{MODEL_FAMILY}/{repeat_index:02d} passed"
                "files, SANY and TLC; stop repair."
            )
        elif repair_rounds >= MAX_REPAIR_ROUNDS:
            stop_reason = "repair_limit"
            print(
                f"Maximum repair rounds {MAX_REPAIR_ROUNDS} reached; stop repair."
            )
        else:
            stop_reason = current_stage

    except Exception as exc:
        stop_reason = "pipeline_error"
        apply_process_failure(result, "pipeline", str(exc))
        error_counter += 1
        save_error(error_counter, "pipeline", str(exc))
        print(
            f"{MODEL_FAMILY}/{repeat_index:02d} pipeline exception: {exc}"
        )
    finally:
        # The interface check is always executed once after the loop completely ends; it only records, does not provide feedback, and does not modify code.
        evaluate_interface_contract(result, helper_hash)
        result["api_calls"] = api_calls
        result["repair_rounds"] = repair_rounds
        result["prompt_tokens"] = usage_total["prompt_tokens"]
        result["completion_tokens"] = usage_total["completion_tokens"]
        result["total_tokens"] = usage_total["total_tokens"]
        result["stop_reason"] = stop_reason
        result["finished_at"] = now_text()
        print_validation_summary(result)
        write_result(result)
        print(f"Result file: {RESULT_PATH}")
        if INTERFACE_LOG_PATH.is_file():
            print(f"Interface not passed, report: {INTERFACE_LOG_PATH}")
        else:
            print("Interface check passed, no additional interface report generated.")
        if TLC_LOG_PATH.is_file():
            print(f"TLC passed output: {TLC_LOG_PATH}")
        error_files = (
            sorted(ERROR_DIR.glob("err[0-9][0-9]_*.txt"))
            if ERROR_DIR.is_dir()
            else []
        )
        if error_files:
            print(
                f"Failure records: {len(error_files)} total,"
                f"located at {ERROR_DIR}"
            )

    return result


def main() -> int:
    validate_fixed_inputs()
    result = run_one_experiment()
    print("\n=== Qdrant this model experiment completed ===")
    print(
        f"{result.get('model_family')}/"
        f"{int(result.get('repeat_index', 0)):02d}: recorded"
    )
    return 0



if __name__ == "__main__":
    raise SystemExit(main())
