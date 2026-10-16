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

# ============================== 可调参数 ==============================

# ============================== DeepSeek 固定配置 ==============================
# 本脚本只用于 DeepSeek 系列，结果固定写入 output1/ds/01、02、03...
# 切换 DeepSeek 的具体型号时，只需修改 MODEL 默认值，
# 或设置环境变量 DEEPSEEK_MODEL。
MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-v4-pro").strip()

PROVIDER = "deepseek"
MODEL_FAMILY = "ds"
EXPERIMENT_GROUP = "t1"
BASE_URL = os.getenv(
    "DEEPSEEK_BASE_URL",
    "https://api.deepseek.com",
).strip()
API_KEY_ENV = "DEEPSEEK_API_KEY"

# DeepSeek 调用使用 thinking 参数；该字段仅为结果配置兼容保留。
REASONING_EFFORT = ""


API_TIMEOUT_SECONDS = int(os.getenv("FORMAL_API_TIMEOUT", "900"))
MAX_OUTPUT_TOKENS = int(os.getenv("FORMAL_MAX_OUTPUT_TOKENS", "50000"))
API_RETRIES = int(os.getenv("FORMAL_API_RETRIES", "3"))
SMOKE_SECONDS = int(os.getenv("TLC_SMOKE_SECONDS", "60"))
SANY_TIMEOUT_SECONDS = int(os.getenv("SANY_TIMEOUT_SECONDS", "120"))
JAVA_BIN = os.getenv("JAVA_BIN", "java")
JAVA_HEAP = os.getenv("TLC_JAVA_HEAP", "2g")
TLC_WORKERS = os.getenv("TLC_WORKERS", "1")
MAX_REPAIR_ROUNDS = 0
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
1. 必须以磁盘当前版本为基线进行最小范围增量修复，不得全量重写。
2. 不得修改、输出、删除或重命名 Qdrant.cfg 和 QCfgHelpers.tla。
3. 不得删除、改名、注释或弱化 cfg 要求的 invariant。
4. 不得使用 invariant == TRUE、Next == FALSE、纯 UNCHANGED Next、
   固定空查询结果或永久不可执行动作绕过错误。
5. 每个 action 必须完整指定 next-state；未改变变量显式 UNCHANGED。
6. 本轮只修复文件提取、SANY 编译或 TLC 报告的当前错误；
   不根据接口契约检查结果修改代码。
7. 只返回本轮实际修改或缺失文件的完整内容，不得返回解释。
""".strip()


class PipelineError(RuntimeError):
    pass


def find_project_root() -> Path:
    start = Path(__file__).resolve().parent
    for candidate in [start, *start.parents]:
        if (candidate / "docs").is_dir() and (candidate / "milvus").is_dir() and (candidate / "output1").is_dir():
            return candidate
    raise FileNotFoundError("无法定位包含 docs、milvus、output1 的 formalization 项目根目录。")


ROOT = find_project_root()
DOCS_DIR = ROOT / "docs"
TLA2TOOLS_JAR = DOCS_DIR / "tla2tools.jar"
MILVUS_DIR = ROOT / "milvus"
OUTPUT1_DIR = ROOT / "output1"
MODEL_DIR = OUTPUT1_DIR / MODEL_FAMILY
GROUP_DIR = OUTPUT1_DIR / EXPERIMENT_GROUP
HELPER_SOURCE_PATH = OUTPUT1_DIR / "QCfgHelpers.tla"

# 以下路径在每次启动时由 configure_new_run_paths() 指向新的 01、02、03... 目录。
RUN_DIR = GROUP_DIR / "__pending__"
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
    required = [FRONTIER_PATH, QDRANT_SPEC_PATH, INTERFACE_PATH, CFG_PATH, HELPER_SOURCE_PATH, TLA2TOOLS_JAR]
    required.extend(MILVUS_DIR / name for name in MILVUS_ORDER)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("以下输入文件不存在：\n" + "\n".join(missing))
    if not MODEL:
        raise EnvironmentError("DEEPSEEK_MODEL / MODEL 不能为空。")
    if not os.getenv(API_KEY_ENV):
        raise EnvironmentError(
            f"未设置 API Key 环境变量：{API_KEY_ENV}。"
        )


def create_next_numeric_run_directory() -> Tuple[Path, int]:
    """
    在 output1/t1/ 下创建下一个 01、02、03... 目录。
    每次运行使用新的编号，已有实验目录不覆盖。
    """
    global MODEL_DIR, GROUP_DIR

    MODEL_DIR = OUTPUT1_DIR / MODEL_FAMILY
    GROUP_DIR = OUTPUT1_DIR / EXPERIMENT_GROUP
    GROUP_DIR.mkdir(parents=True, exist_ok=True)

    existing = [
        int(path.name)
        for path in GROUP_DIR.iterdir()
        if path.is_dir()
        and re.fullmatch(r"\d{2,}", path.name)
    ]
    next_index = max(existing, default=0) + 1

    while True:
        run_dir = GROUP_DIR / f"{next_index:02d}"
        try:
            run_dir.mkdir(
                parents=False,
                exist_ok=False,
            )
            return run_dir, next_index
        except FileExistsError:
            next_index += 1

def configure_run_paths() -> Tuple[Path, int]:
    """为 output1/t1 分配下一次独立实验目录。"""
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
    初始化本次新目录。

    QCfgHelpers.tla 的唯一维护副本位于：
        output1/QCfgHelpers.tla

    每次实验会自动复制到本组本次编号目录的 Qdrant 子目录。
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
你需要生成一套完整的 Qdrant Frontier-based TLA+ 模型。

【实验流程】
本组不提供《TLA生成易错规则.md》。
初始生成后只进行文件、SANY 和 TLC 检查。
接口契约只在全部执行流程结束后评价一次，不反馈模型、不修改代码。

【约束优先级】
1. Qdrant生成接口约束.md
2. Qdrant规约.md
3. Frontier通用方法.md
4. Milvus 参考代码

【固定要求】
- 只能输出这 8 个文件：{', '.join(REQUIRED_FILES)}。
- 不得输出或修改 QCfgHelpers.tla 和 Qdrant.cfg。
- 严格保持：QCore -> QAuth -> QWrite -> QReplica -> QMigrate
  -> QSearch -> QFrontierInterface -> QIntegrated。
- QSearch 定义 SearchEligibleSet，不得前向引用任何 Frontier operator。
- QFrontierInterface EXTENDS QSearch，只定义 Frontier 和安全性质，
  不声明变量、不定义动作。
- 成功 Search 必须完整返回 SearchEligibleSet，不得使用任意子集。
- 每个 action 必须完整指定 next-state，未修改变量显式 UNCHANGED。
- 不得使用恒真 invariant、Next == FALSE、固定空 Frontier
  或固定空查询结果绕过验证。

【严格输出格式】
不要使用 Markdown 围栏。每个文件使用：
===== FILE: 文件名 =====
<完整文件内容>
===== END FILE =====

================ Frontier通用方法.md ================
{read_text(FRONTIER_PATH)}

================ Qdrant规约.md ================
{read_text(QDRANT_SPEC_PATH)}

================ Qdrant生成接口约束.md ================
{read_text(INTERFACE_PATH)}

================ 固定 Qdrant.cfg（只读） ================
{read_text(CFG_PATH)}

================ 固定 QCfgHelpers.tla（只读） ================
{read_text(HELPER_PATH)}

================ Milvus 参考代码 ================
{build_milvus_bundle()}
""".strip()

def create_client() -> OpenAI:
    return OpenAI(
        api_key=os.environ[API_KEY_ENV],
        base_url=BASE_URL,
        timeout=API_TIMEOUT_SECONDS,
        max_retries=0,
    )


def _usage_from_chat(response) -> Dict[str, int]:
    usage = getattr(response, "usage", None)
    return {
        "prompt_tokens": int(getattr(usage, "prompt_tokens", 0) or 0),
        "completion_tokens": int(
            getattr(usage, "completion_tokens", 0) or 0
        ),
        "total_tokens": int(getattr(usage, "total_tokens", 0) or 0),
    }


def _usage_from_response(response) -> Dict[str, int]:
    usage = getattr(response, "usage", None)
    return {
        "prompt_tokens": int(getattr(usage, "input_tokens", 0) or 0),
        "completion_tokens": int(
            getattr(usage, "output_tokens", 0) or 0
        ),
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
            if PROVIDER == "openai":
                kwargs = {
                    "model": MODEL,
                    "instructions": system_prompt,
                    "input": prompt,
                    "max_output_tokens": MAX_OUTPUT_TOKENS,
                    "store": False,
                }
                if REASONING_EFFORT:
                    kwargs["reasoning"] = {
                        "effort": REASONING_EFFORT
                    }
                response = client.responses.create(**kwargs)
                content = getattr(response, "output_text", "") or ""
                usage_dict = _usage_from_response(response)
            else:
                kwargs = {
                    "model": MODEL,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": prompt},
                    ],
                    "stream": False,
                    "max_tokens": MAX_OUTPUT_TOKENS,
                }
                if PROVIDER == "deepseek":
                    response = client.chat.completions.create(
                        **kwargs,
                        extra_body={"thinking": {"type": "enabled"}},
                    )
                else:
                    response = client.chat.completions.create(**kwargs)
                content = response.choices[0].message.content or ""
                usage_dict = _usage_from_chat(response)

            if not content.strip():
                raise PipelineError(
                    f"模型 {MODEL_FAMILY}/{MODEL} 返回了空内容。"
                )
            return content, usage_dict
        except Exception as exc:
            last_error = exc
            if attempt >= API_RETRIES:
                break
            wait_seconds = min(30, 2 ** attempt)
            print(
                f"{MODEL_FAMILY} API 调用失败"
                f"（{attempt}/{API_RETRIES}）：{exc}"
            )
            time.sleep(wait_seconds)
    raise PipelineError(
        f"模型 {MODEL_FAMILY}/{MODEL} API 调用最终失败：{last_error}"
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
            errors.append(f"缺少文件：{name}")
            continue
        code = read_text(path)
        if not code.strip():
            errors.append(f"空文件：{name}")
            continue
        if "```" in code:
            errors.append(f"残留 Markdown 围栏：{name}")
        expected = Path(name).stem
        header = re.search(r"(?m)^-{4,}\s*MODULE\s+([A-Za-z0-9_]+)\s*-{4,}\s*$", code)
        if not header:
            errors.append(f"缺少标准 MODULE 头：{name}")
        elif header.group(1) != expected:
            errors.append(f"MODULE 名错误：{name} -> {header.group(1)}")
        if not re.search(r"(?m)^={4,}\s*$", code.rstrip()):
            errors.append(f"模块末尾缺少 ====：{name}")
    unexpected = sorted(actual_tla - allowed)
    if unexpected:
        errors.append("出现额外 TLA 文件：" + ", ".join(unexpected))
    for path in QDRANT_DIR.iterdir():
        if path.is_file() and path.suffix.lower() != ".tla":
            errors.append(f"Qdrant 目录中出现非 TLA 文件：{path.name}")
    return errors


def check_interface_contract(helper_hash: str) -> Tuple[bool, str]:
    """
    在本次生成与运行流程结束后检查固定生成接口。

    这里只检查 Qdrant生成接口约束中可机械确认的硬性契约，
    不规定 operator 内部必须采用哪一种等价写法，也不判断业务语义质量。
    """
    errors: List[str] = []

    # 固定核心模块与只读 helper。
    for file_name in REQUIRED_FILES:
        if not (QDRANT_DIR / file_name).is_file():
            errors.append(f"接口要求的模块缺失：{file_name}")

    if not HELPER_PATH.is_file():
        errors.append("固定 QCfgHelpers.tla 缺失。")
    elif sha256_file(HELPER_PATH) != helper_hash:
        errors.append("固定 QCfgHelpers.tla 哈希值发生变化。")

    clean_codes: Dict[str, str] = {}
    for file_name in REQUIRED_FILES:
        path = QDRANT_DIR / file_name
        if path.is_file():
            clean_codes[file_name] = remove_tla_comments(read_text(path))

    # 固定模块依赖链。
    for file_name, parent in BUSINESS_PARENT.items():
        code = clean_codes.get(file_name, "")
        if code and not re.search(
            rf"\b{re.escape(parent)}\b",
            extends_block(code),
        ):
            errors.append(f"{file_name} 必须 EXTENDS {parent}。")

    integrated_code = clean_codes.get("QIntegrated.tla", "")
    integrated_extends = extends_block(integrated_code)
    for parent in ("QFrontierInterface", "QCfgHelpers"):
        if integrated_code and not re.search(
            rf"\b{re.escape(parent)}\b",
            integrated_extends,
        ):
            errors.append(f"QIntegrated.tla 必须 EXTENDS {parent}。")

    # 接口文档规定的常量、变量和 operator 名称。
    core_constants = declared_names(
        clean_codes.get("QCore.tla", ""),
        "CONSTANTS?",
    )
    for constant in CORE_CONSTANTS:
        if constant not in core_constants:
            errors.append(f"QCore.tla 缺少接口常量：{constant}")

    for file_name, required_vars in MODULE_REQUIRED_VARIABLES.items():
        variables = declared_names(
            clean_codes.get(file_name, ""),
            "VARIABLES?",
        )
        for variable in required_vars:
            if variable not in variables:
                errors.append(f"{file_name} 缺少接口变量：{variable}")

    for file_name, operators in MODULE_REQUIRED_OPERATORS.items():
        code = clean_codes.get(file_name, "")
        for operator in operators:
            if not code or not operator_defined(code, operator):
                errors.append(f"{file_name} 缺少接口 operator：{operator}")

    # Frontier 接口模块必须保持无状态。
    frontier_code = clean_codes.get("QFrontierInterface.tla", "")
    if re.search(r"(?m)^\s*VARIABLES?\b", frontier_code):
        errors.append("QFrontierInterface.tla 不得声明状态变量。")
    if re.search(r"\b[A-Za-z_][A-Za-z0-9_]*'", frontier_code):
        errors.append("QFrontierInterface.tla 不得更新状态变量。")
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
                "QFrontierInterface.tla 不得定义状态或业务动作："
                + forbidden_op
            )

    # 固定 cfg 所引用的不变量必须存在。
    all_code = "\n".join(clean_codes.values())
    for invariant in CFG_INVARIANTS:
        if not operator_defined(all_code, invariant):
            errors.append(f"Qdrant.cfg 引用的 invariant 不存在：{invariant}")

    # 接口文档明确禁止的直接退化写法。
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
            errors.append(f"{file_name} 将 Next 退化为常量。")
        for invariant in key_invariants:
            if re.search(
                rf"(?m)^\s*{re.escape(invariant)}"
                rf"(?:\s*\([^\n]*\))?\s*==\s*TRUE\s*$",
                code,
            ):
                errors.append(
                    f"{file_name} 将关键 invariant {invariant} 退化为 TRUE。"
                )
        if re.search(
            r"(?m)^\s*(?:WriteFrontier|CommitFrontier|"
            r"ReplicaFrontier|QueryFrontier|MigrateFrontier|"
            r"SearchFrontier)(?:\s*\([^\n]*\))?\s*==\s*\{\}\s*$",
            code,
        ):
            errors.append(f"{file_name} 将关键 Frontier 固定为空集。")
        if re.search(r"searchResult'\s*=\s*\{\}", code):
            errors.append(f"{file_name} 将成功查询结果固定为空集。")

    # cfg model value 不得写死在业务模块中。
    model_values = (
        "P1", "P2", "N1", "N2", "N3", "S1", "C1",
        "PT1", "PT2", "R1", "R2", "R3",
    )
    for model_value in model_values:
        for file_name, code in clean_codes.items():
            if re.search(rf"\b{model_value}\b", code):
                errors.append(
                    f"{file_name} 硬编码了 cfg model value：{model_value}"
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
            "已确认固定模块、依赖、接口名称、只读 helper、cfg invariant "
            "和明确防退化条款；未检查唯一实现形式或业务语义正确性。\n"
        )

    if errors:
        write_text(INTERFACE_LOG_PATH, report)
    elif INTERFACE_LOG_PATH.exists():
        INTERFACE_LOG_PATH.unlink()
    return not errors, report

def new_validation_status() -> Dict[str, object]:
    """创建各检查项的独立状态，不生成 overall 字段。"""
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
    """为各检查项保存独立、简短的失败原因。"""
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
    """把本轮最新检查状态写入最终结果。"""
    result.update(status)
    result.update(reasons)
    result["failed_checks"] = collect_failed_checks(
        status,
        str(reasons.get("process_reason", "none")),
    )


def apply_extraction_failure(result: Dict[str, object], details: str) -> None:
    """记录初始 API 响应未能形成规定文件集的情况。"""
    status = new_validation_status()
    reasons = new_validation_reasons()
    status["file_extract_result"] = "fail"
    status["file_completeness_result"] = "fail"

    concise = concise_failure_reason("extract", details)
    reasons["file_extract_reason"] = concise
    reasons["file_completeness_reason"] = "未形成完整且唯一的规定 TLA+ 文件集"
    apply_validation_outcome(result, status, reasons)


def apply_process_failure(
    result: Dict[str, object],
    stage: str,
    details: str,
) -> None:
    """记录 API、修复调用或脚本管线异常，不覆盖已有检查结果。"""
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
    对当前磁盘上的最终代码执行接口契约检查并写回结果。

    该检查可在 SANY/TLC 成功或失败后执行；因此即使运行始终未通过，
    仍能看到最终代码是否遵守固定生成接口。
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
    自动运行阶段只处理：文件 -> SANY -> TLC。

    接口契约不与 SANY/TLC 错误混合，统一在运行阶段结束后单独检查。
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
            "缺少规定文件：" + ", ".join(missing)
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
            sections.append(f"===== {name} =====\n文件不存在。")
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

    # TLC 失败输出会进入 error.log；只有 TLC 通过时，
    # 才单独保存本次成功运行的完整输出，供后续查看状态统计。
    if ok:
        write_text(TLC_LOG_PATH, output)
    elif TLC_LOG_PATH.exists():
        # 当前实验目录通常是新建的；这里用于避免意外残留旧成功结果。
        TLC_LOG_PATH.unlink()

    return ok, output, timed_out

def compact_error(text: str) -> str:
    if len(text) <= MAX_ERROR_PROMPT_CHARS:
        return text
    head = MAX_ERROR_PROMPT_CHARS // 3
    tail = MAX_ERROR_PROMPT_CHARS - head
    return text[:head] + "\n\n... 中间内容因节省 API 输入而省略 ...\n\n" + text[-tail:]


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
    修复阶段只发送通用 TLA+/cfg/next-state 规则。
    固定模块接口、QSearch/Frontier 分层和业务接口条款不重复发送。
    """
    sections = split_rule_sections(read_text(RULES_PATH))
    generic_heading_keywords = (
        "字符", "语法", "extends", "operator", "cfg", "helper",
        "函数", "集合", "记录", "let", "作用域", "变量", "init",
        "typeok", "next-state", "next、spec", "next", "spec",
        "invariant", "错误阶段", "增量修复", "修复提示",
    )
    excluded_heading_keywords = (
        "固定文件", "强制顺序", "qsearch", "qfrontierinterface",
        "frontier 常见", "权限", "写入", "迁移", "静态预检查",
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
            + "\n\n（通用规则片段已按输入上限截断。）"
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
    return "\n\n".join(sections) or "（当前没有可读取的生成文件。）"


def build_repair_prompt(
    stage: str,
    error_text: str,
    relevant_files: Sequence[str],
) -> str:
    missing = [
        name
        for name in REQUIRED_FILES
        if not (QDRANT_DIR / name).is_file()
    ]

    return f"""
请根据当前失败信息，在磁盘已有版本基础上完成一次最小范围增量修复。

【本轮只处理的失败阶段】
{stage}

【缺失文件】
{', '.join(missing) if missing else '无'}

【固定修复约束】
{FIXED_REPAIR_CONTRACT}

【当前错误】
{compact_error(error_text)}

【当前相关代码】
{build_current_code_bundle(relevant_files)}

【输出格式】
只返回本轮实际修改或补充的文件，最多 {MAX_REPAIR_FILES} 个；
不得使用 Markdown 围栏：
===== FILE: Qxxx.tla =====
<修改后的完整文件内容>
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
    """把完整错误输出压缩成适合 result.txt 的一行摘要。"""
    text = str(details or "").strip()
    if not text:
        return "未提供错误详情"

    if stage in {"extract", "file"}:
        return "；".join(line.strip() for line in text.splitlines() if line.strip())[:500]

    if stage == "interface_contract":
        numbered = re.findall(r"(?m)^\s*\d+\.\s*(.+)$", text)
        if numbered:
            preview = "；".join(item.strip() for item in numbered[:3])
            if len(numbered) > 3:
                preview += f"；另有{len(numbered) - 3}项"
            return f"接口契约未通过：{preview}"
        return "接口契约未通过，详见 interface_contract_report.txt"

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
            failed_module = "未知模块"

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
                ",": "逗号",
                ":": "冒号",
                ")": "右括号",
                "(": "左括号",
            }.get(symbol, f"符号 {symbol}")
            return (
                f"{failed_module} SANY解析失败：第{line_no}行第{column_no}列，"
                f"在 {token} 附近出现非法{symbol_name}"
            )

        if location:
            line_no, column_no = location.groups()
            return f"{failed_module} SANY检查失败：第{line_no}行第{column_no}列"

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
                return f"{failed_module} SANY检查失败：{match.group(0).strip()[:350]}"
        return f"{failed_module} 未通过 SANY 检查"

    if stage == "tlc":
        invariant = re.search(
            r"Invariant\s+([A-Za-z_][A-Za-z0-9_]*)\s+is violated",
            text,
            flags=re.IGNORECASE,
        )
        if invariant:
            return f"TLC一分钟测试失败：不变量 {invariant.group(1)} 被违反"

        for pattern, message in (
            (r"Deadlock reached", "检测到死锁"),
            (r"ConfigFileException[^\n]*", None),
            (r"Successor state is not completely specified[^\n]*", None),
            (r"Java ran out of memory", "Java内存不足"),
            (r"OutOfMemoryError", "Java内存不足"),
        ):
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if match:
                return f"TLC一分钟测试失败：{message or match.group(0).strip()[:350]}"
        return "TLC一分钟测试未通过，详见对应 errNN_tlc.txt"

    if stage == "api_or_repair":
        return f"API或增量修复失败：{text.splitlines()[0][:450]}"

    if stage == "pipeline":
        return f"脚本管线异常：{text.splitlines()[0][:450]}"

    return text.splitlines()[0][:500]

def print_validation_summary(result: Dict[str, object]) -> None:
    """在终端中显示每项独立结果，不合并成 overall。"""
    status_text = {
        "pass": "通过",
        "fail": "未通过",
        "not_run": "未执行",
        "pending": "待人工检查",
    }
    items = (
        ("文件提取", "file_extract_result"),
        ("文件完整性", "file_completeness_result"),
        ("SANY 编译", "sany_result"),
        ("TLC 一分钟测试", "tlc_smoke_result"),
        ("接口契约检查", "interface_contract_result"),
        ("人工逻辑检查", "manual_logic_result"),
    )

    print("\n检查结果汇总：")
    for label, field in items:
        value = str(result.get(field, "not_run"))
        print(f"  {label}：{status_text.get(value, value)}")

    if str(result.get("tlc_smoke_result", "not_run")) != "not_run":
        end_value = str(result.get("tlc_smoke_end", "not_run"))
        end_text = {
            "timeout": "达到一分钟后终止",
            "completed": "TLC 自行结束",
            "not_run": "未执行",
        }.get(end_value, end_value)
        print(f"  TLC 结束方式：{end_text}")

    failed_checks = str(result.get("failed_checks", "none"))
    print(f"  未通过项：{'无' if failed_checks == 'none' else failed_checks}")

    reason_fields = (
        ("文件提取原因", "file_extract_reason"),
        ("文件完整性原因", "file_completeness_reason"),
        ("SANY 原因", "sany_reason"),
        ("TLC 原因", "tlc_smoke_reason"),
        ("接口契约原因", "interface_contract_reason"),
        ("过程异常", "process_reason"),
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
        f"\n=== Qdrant DeepSeek T1/{repeat_index:02d}："
        "一次生成 + 文件/SANY/TLC一次检查 + 最终接口评价 ==="
    )
    print(f"实验目录：{run_dir}")
    print(
        f"实验组：T1；实际模型："
        f"{MODEL_FAMILY} -> {PROVIDER}/{MODEL}"
    )

    helper_hash = sha256_file(HELPER_PATH)
    client = create_client()
    jar_path = TLA2TOOLS_JAR

    usage_total = {
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
    }
    api_calls = 0
    error_counter = 0
    stop_reason = "none"

    result: Dict[str, object] = {
        "group": "T1",
        "model_family": MODEL_FAMILY,
        "provider": PROVIDER,
        "model": MODEL,
        "base_url": BASE_URL,
        "repeat_index": f"{repeat_index:02d}",
        "started_at": now_text(),
        "check_scheme": (
            "t1_one_shot_execution_then_final_interface_v1"
        ),
        "rules_usage": "not_used",
        "repair_usage": "not_used",
        "interface_contract_usage": (
            "final_evaluation_only_no_feedback"
        ),
        "max_repair_rounds": 0,
        "api_calls": 0,
        "repair_rounds": 0,
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
        "helper_sha256": helper_hash,
        "interface_sha256": sha256_file(INTERFACE_PATH),
        "qdrant_spec_sha256": sha256_file(
            QDRANT_SPEC_PATH
        ),
        "frontier_sha256": sha256_file(FRONTIER_PATH),
        "rules_sha256": "not_used",
        "cfg_sha256": sha256_file(CFG_PATH),
        **new_validation_status(),
        "failed_checks": "none",
        **new_validation_reasons(),
    }

    try:
        print("正在进行 T1 初始完整生成……")
        response_text, usage = call_model(
            client,
            build_initial_prompt(),
            (
                "你是严格的 TLA+ 形式化建模工程师。"
                "根据给定接口、规约和参考代码一次生成完整模型。"
            ),
        )
        api_calls += 1
        add_usage(usage_total, usage)

        files, unexpected = extract_tla_files(
            response_text
        )
        write_generated_files(files)
        missing = sorted(
            set(REQUIRED_FILES) - set(files)
        )

        if unexpected or missing:
            parts: List[str] = []
            if missing:
                parts.append(
                    "缺少可提取文件："
                    + ", ".join(missing)
                )
            if unexpected:
                parts.append(
                    "初始响应包含禁止的额外文件："
                    + ", ".join(unexpected)
                )
            current_stage = "extract"
            current_error = "\n".join(parts)
            apply_extraction_failure(
                result,
                current_error,
            )
        else:
            (
                status,
                reasons,
                current_stage,
                current_error,
            ) = validate_execution(jar_path)
            apply_validation_outcome(
                result,
                status,
                reasons,
            )

        if current_stage == "execution_success":
            stop_reason = "execution_success"
            print(
                "T1 一次生成后已通过文件、SANY和TLC。"
            )
        else:
            stop_reason = current_stage
            error_counter += 1
            save_error(
                error_counter,
                current_stage,
                current_error,
            )
            print(
                "T1 一次检查结束，不调用模型修复。"
            )

    except Exception as exc:
        stop_reason = "pipeline_error"
        apply_process_failure(
            result,
            "pipeline",
            str(exc),
        )
        error_counter += 1
        save_error(
            error_counter,
            "pipeline",
            str(exc),
        )
        print(f"T1 管线异常：{exc}")

    finally:
        # 一次生成及执行检查结束后评价接口，不反馈、不修改代码。
        evaluate_interface_contract(
            result,
            helper_hash,
        )
        result["api_calls"] = api_calls
        result["repair_rounds"] = 0
        result["prompt_tokens"] = (
            usage_total["prompt_tokens"]
        )
        result["completion_tokens"] = (
            usage_total["completion_tokens"]
        )
        result["total_tokens"] = (
            usage_total["total_tokens"]
        )
        result["stop_reason"] = stop_reason
        result["finished_at"] = now_text()

        print_validation_summary(result)
        write_result(result)
        print(f"结果文件：{RESULT_PATH}")

        if INTERFACE_LOG_PATH.is_file():
            print(
                "接口未通过，报告："
                f"{INTERFACE_LOG_PATH}"
            )
        else:
            print(
                "接口检查通过，未生成额外接口报告。"
            )

        if TLC_LOG_PATH.is_file():
            print(f"TLC通过输出：{TLC_LOG_PATH}")

        error_files = (
            sorted(
                ERROR_DIR.glob(
                    "err[0-9][0-9]_*.txt"
                )
            )
            if ERROR_DIR.is_dir()
            else []
        )
        if error_files:
            print(
                f"失败记录：共 {len(error_files)} 个，"
                f"位于 {ERROR_DIR}"
            )

    return result

def main() -> int:
    validate_fixed_inputs()
    result = run_one_experiment()
    print("\n=== Qdrant 本次模型实验完成 ===")
    print(
        f"T1/{result.get('model_family')}/"
        f"{int(result.get('repeat_index', 0)):02d}: 已记录"
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())