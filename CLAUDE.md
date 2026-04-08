# CLAUDE.md — Symphony Repository Guide

Symphony is an AI agent orchestration service. It polls a Linear project for work, creates isolated per-issue workspaces, launches Codex in app-server mode, and keeps agents working until issues reach a terminal state. This document explains the codebase for AI assistants.

> **Status:** Engineering preview — prototype software for evaluation in trusted environments.

---

## Repository Layout

```
symphony/
├── SPEC.md              # Language-agnostic specification (authoritative)
├── README.md            # Project overview and quickstart
├── CLAUDE.md            # This file
├── elixir/              # Reference Elixir/OTP implementation
│   ├── lib/             # Application source code
│   ├── test/            # ExUnit test suite
│   ├── docs/            # Developer reference docs
│   ├── WORKFLOW.md      # In-repo workflow contract (config + agent prompt)
│   ├── AGENTS.md        # Codebase conventions for agents
│   ├── mix.exs          # Build manifest and dependencies
│   └── Makefile         # Quality-gate commands
└── .codex/
    └── skills/          # Repo-local Codex skills (commit, push, pull, land, linear, debug)
```

**The spec is authoritative.** `SPEC.md` defines the intended behavior. The Elixir implementation may be a superset but must not conflict with it. Update the spec in the same PR when behavior changes meaningfully.

---

## Elixir Implementation

### Runtime Requirements

| Tool | Version |
|------|---------|
| Elixir | 1.19.x |
| Erlang/OTP | 28 |
| Runtime manager | [mise](https://mise.jdx.dev/) |

```bash
cd elixir
mise trust && mise install
mise exec -- elixir --version
```

### Build and Run

```bash
# Install dependencies
mise exec -- mix setup

# Build the escript binary
mise exec -- mix build          # → bin/symphony

# Run with a workflow file
mise exec -- ./bin/symphony ./WORKFLOW.md

# Optional flags
#   --port 4000           enables Phoenix web dashboard + JSON API
#   --logs-root /tmp/logs  writes logs to a custom directory
```

### Quality Gate (run before handoff)

```bash
make all        # format check + lint + coverage + dialyzer
```

Individual targets:

| Command | What it does |
|---------|-------------|
| `make fmt` | Format source |
| `make fmt-check` | Check formatting (CI) |
| `make lint` | `mix specs.check` + `credo --strict` |
| `make test` | ExUnit test suite |
| `make coverage` | Tests with 100% coverage threshold |
| `make dialyzer` | Dialyzer type checking |
| `make e2e` | Live integration test (requires `LINEAR_API_KEY`) |

---

## Source Code Structure (`elixir/lib/`)

### Core Domain (`symphony_elixir/`)

| File | Role |
|------|------|
| `orchestrator.ex` | Central GenServer polling loop; drives issue lifecycle and concurrency |
| `agent_runner.ex` | Launches Codex in a workspace; manages turn retries |
| `workspace.ex` | Creates/destroys isolated per-issue workspaces (local + SSH) |
| `config.ex` | Typed runtime config loaded from WORKFLOW.md front matter |
| `config/schema.ex` | Ecto schema and validation for all config keys |
| `workflow.ex` | WORKFLOW.md loader/watcher |
| `workflow_store.ex` | Caches and hot-reloads workflow config |
| `tracker.ex` | Adapter behaviour for issue trackers |
| `prompt_builder.ex` | Jinja2-style prompt rendering for Codex sessions |
| `path_safety.ex` | Validates workspace paths stay under the configured root |
| `status_dashboard.ex` | Terminal ANSI dashboard (updates every second) |
| `http_server.ex` | Phoenix HTTP server wrapper |
| `log_file.ex` | Structured logging setup |
| `ssh.ex` | Remote workspace execution over SSH |
| `cli.ex` | Escript entry point; parses CLI args |

### Linear Integration (`linear/`)

| File | Role |
|------|------|
| `client.ex` | GraphQL queries against `https://api.linear.app/graphql` |
| `adapter.ex` | Implements the `Tracker` behaviour |
| `issue.ex` | Normalized issue struct |

### Codex Protocol (`codex/`)

| File | Role |
|------|------|
| `app_server.ex` | JSON-RPC 2.0 over stdio — manages Codex subprocess lifecycle |
| `dynamic_tool.ex` | Tool execution; bridges MCP-style tool calls |

### Web Layer (`symphony_elixir_web/`)

| File | Role |
|------|------|
| `router.ex` | Routes: `/`, `/api/v1/*` |
| `live/dashboard_live.ex` | Real-time LiveView dashboard |
| `controllers/observability_api_controller.ex` | JSON API endpoints |
| `presenter.ex` | Formats data for UI/API responses |

### Mix Tasks (`lib/mix/tasks/`)

| Task | Purpose |
|------|---------|
| `specs.check` | Enforces `@spec` on all public functions |
| `pr_body.check` | Validates PR body against the template |
| `workspace.before_remove` | Cleanup hook run before workspace deletion |

---

## OTP Supervision Tree

```
SymphonyElixir.Application
├── Phoenix.PubSub          (internal pub/sub)
├── Task.Supervisor         (async tasks)
├── WorkflowStore           (watches WORKFLOW.md for changes)
├── Orchestrator            (polling GenServer)
├── HttpServer              (Phoenix endpoint, optional)
└── StatusDashboard         (terminal UI GenServer)
```

---

## Configuration (WORKFLOW.md)

All runtime configuration comes from the YAML front matter in `WORKFLOW.md`. The file also contains the Markdown body used as the Codex session prompt.

### Key Config Keys

```yaml
tracker:
  kind: linear
  project_slug: "..."
  api_key: $LINEAR_API_KEY       # or set env var LINEAR_API_KEY
  active_states: [Todo, "In Progress", Merging, Rework]
  terminal_states: [Closed, Cancelled, Duplicate, Done]

polling:
  interval_ms: 5000

workspace:
  root: ~/code/workspaces          # ~ and $VAR are expanded

hooks:
  after_create: |                  # runs after workspace directory is created
    git clone git@github.com:org/repo.git .
    mise trust && mise exec -- mix deps.get
  before_remove: |                 # runs before workspace is deleted
    cd elixir && mise exec -- mix workspace.before_remove

agent:
  max_concurrent_agents: 10
  max_turns: 20                    # max back-to-back turns per agent invocation

codex:
  command: codex app-server        # shell command; $VAR expanded by shell
  approval_policy: never           # or object-form {"reject": {...}}
  thread_sandbox: workspace-write  # read-only | workspace-write | danger-full-access
  turn_sandbox_policy:
    type: workspaceWrite           # passed through to Codex unchanged

server:
  port: 4000                       # optional; enables Phoenix dashboard
```

### Accessing Config in Code

Always use `SymphonyElixir.Config.settings!()` rather than ad-hoc environment reads. If a new config key is needed, add it to `config/schema.ex` with proper validation and defaults.

### Hot Reload

`WorkflowStore` watches the file for changes. A successful reload takes effect immediately. If a reload fails, Symphony keeps running with the last known-good config.

---

## Coding Conventions

### Required: `@spec` on Every Public Function

All `def` functions in `lib/` must have an adjacent `@spec`. This is enforced by `mix specs.check` (part of `make lint`).

- `defp` specs are optional but encouraged.
- `@impl true` callback implementations are exempt.

```elixir
# Good
@spec run(map()) :: {:ok, pid()} | {:error, String.t()}
def run(opts) do ...

# Bad — missing @spec
def run(opts) do ...
```

### Error Handling

- Return `{:ok, value}` / `{:error, reason}` tuples — no exceptions for control flow.
- Raise `ArgumentError` or `RuntimeError` for true programming errors.

### Module Boundaries

- Config access always through `SymphonyElixir.Config`.
- Workspace paths always validated through `SymphonyElixir.PathSafety`.
- Never run Codex turns with a cwd inside the source repository.
- Orchestrator state is concurrency-sensitive — preserve retry, reconciliation, and cleanup semantics when modifying it.

### Logging

Follow `elixir/docs/logging.md`. Required fields by context:

| Context | Required Fields |
|---------|----------------|
| Issue-related work | `issue_id`, `issue_identifier` (e.g. `MT-620`) |
| Codex session events | `session_id` |

Log format: `"message key=value key=value"` — explicit key=value pairs for searchable fields.

Logging scopes:
- `AgentRunner`: start/completion/failure with issue context + `session_id`
- `Orchestrator`: dispatch, retry, terminal/non-active transitions, worker exits
- `Codex.AppServer`: session start/completion/error with issue context + `session_id`

### Token Accounting

See `elixir/docs/token_accounting.md` for the full spec. Summary:

- **Preferred source:** `thread/tokenUsage/updated` → `tokenUsage.total` (absolute thread total)
- **Fallback:** `TokenCountEvent.info.total_token_usage`
- **Ignore for totals:** any `.last` / delta field, turn-completed `usage`, generic `params.usage`
- Key accounting by `thread_id`, not issue ID. Multiple turns share one thread.

---

## Testing

### Running Tests

```bash
make test         # run full suite
make coverage     # run with 100% coverage check
mix test test/path/to_test.exs   # run a single file while iterating
```

### Test Conventions

- Framework: ExUnit
- Test helpers via `TestSupport.__using__` macro (sets up workflow files, temp directories)
- Snapshot testing with `SnapshotSupport` for complex UI output
- Temp file cleanup in `on_exit/1` callbacks
- Use the memory tracker backend (`test/support/`) to mock Linear — never hit the real API in unit tests
- Coverage threshold is 100%. Modules excluded from coverage are listed in `mix.exs` under `test_coverage.ignore_modules`.

### Live E2E Tests

```bash
export LINEAR_API_KEY=...
make e2e
```

These tests create real Linear resources, run a real Codex session, and require network access. Do not run in normal CI. Use only when validating the full integration stack.

---

## PR Requirements

PR bodies must follow `.github/pull_request_template.md` exactly. Validate before submitting:

```bash
mix pr_body.check --file /path/to/pr_body.md
```

### Docs Update Policy

When behavior or configuration changes, update docs in the same PR:

- `README.md` (root) — project concept and goals
- `elixir/README.md` — Elixir implementation and run instructions
- `elixir/WORKFLOW.md` — workflow/config contract changes
- `SPEC.md` — if implementation changes alter intended behavior

---

## External Integrations

### Linear

- API: GraphQL at `https://api.linear.app/graphql`
- Auth: `LINEAR_API_KEY` environment variable
- Operations: poll candidate issues, update issue state, create comments
- Module: `SymphonyElixir.Linear.Client`

### Codex App-Server

- Transport: JSON-RPC 2.0 over stdio
- Launched as a subprocess; command is configured in `WORKFLOW.md`
- Session lifecycle: start thread → run turns → stream tool calls → stop
- Module: `SymphonyElixir.Codex.AppServer`

### SSH Workers (Optional)

- Configure `worker.ssh_hosts` in WORKFLOW.md for distributed execution
- Module: `SymphonyElixir.SSH`

---

## Observability

### Terminal Dashboard

Rendered to stdout by `StatusDashboard` (ANSI colors, sparklines for throughput, updates ≥ 1/sec).

### Web Dashboard (optional)

Start with `--port 4000`:

| Path | Description |
|------|-------------|
| `/` | Phoenix LiveView real-time dashboard |
| `/api/v1/state` | Full orchestrator snapshot (JSON) |
| `/api/v1/<issue_identifier>` | Single-issue state (JSON) |
| `/api/v1/refresh` | Trigger immediate poll (POST) |

### Log Files

Written to `./log/` by default (override with `--logs-root`). Per-issue log files include structured key=value pairs for searchability.

---

## Codex Skills (`.codex/skills/`)

Repo-local skills available to Codex agents working in this repository:

| Skill | Purpose |
|-------|---------|
| `commit` | Stage and create git commits |
| `push` | Push branch to remote |
| `pull` | Pull latest from remote |
| `land` | Merge a PR |
| `linear` | Raw Linear GraphQL operations via `linear_graphql` tool |
| `debug` | Debugging utilities |

The `linear` skill depends on Symphony's `linear_graphql` app-server tool being available.
