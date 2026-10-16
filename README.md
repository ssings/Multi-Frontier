# Multi-Frontier

```
Multi-Frontier is a formal modeling method for abstracting data states in distributed database systems. This project uses Python scripts to generate, check, and repair TLA+ formal models for different database systems, and uses the TLC model checker to verify model behavior.

## Directory Structure

```text
Multi-Frontier/
├── docs/
├── milvus/
├── output1/
└── output2/
```

### `docs/`

Contains project documentation and reference materials.

- `Frontier_Method.md`: Describes the general Multi-Frontier modeling method.
- `Qdrant_Specification.md`: Contains the Qdrant-related formal specification.
- `tla2tools.jar`: TLA+/TLC model-checking tool.

### `milvus/`

Contains the core Milvus TLA+ models.

- `MAuth.tla`: Authorization and access control.
- `MCore.tla`: Core system state and operations.
- `MFrontierInterface.tla`: Frontier-related interfaces.
- `MIntegrated.tla`: Integrated model entry point.
- `MMigrate.tla`: Data migration behavior.
- `MQuery.tla`: Query and read behavior.
- `MSync.tla`: Synchronization behavior.
- `MWrite.tla`: Write and update behavior.

### `output1/`

Contains Qdrant-related experiment outputs.

- `gpt/`: Experiments generated through GPT-based workflows.
- `t1/`, `t2/`, and `t3/`: Independent experiment groups.

These directories may contain Python generation scripts, TLA+ models, TLC configuration files, execution logs, result summaries, error reports, and model-checking state files.

### `output2/`

Contains Cassandra-related experiment outputs.

- `gpt/`: GPT-based Cassandra model-generation experiments.
- `stage1/`: Initial planning and specification files.
- `t1/`, `t2/`, and `t3/`: Independent experiment groups.

These directories may contain Python scripts, Cassandra TLA+ modules, TLC configuration files, model-checking results, error reports, repair records, and generated state files.

## General Workflow

The project generally follows these steps:

1. Generate a database model.
2. Generate or update the TLC configuration.
3. Perform structural and semantic checks.
4. Run TLC model checking.
5. Save results, logs, error reports, and model states.

The project combines automated code generation, formal specification, model checking, and experiment result collection for studying distributed database behavior.
\```