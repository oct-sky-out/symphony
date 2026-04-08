# CLAUDE.md — Symphony

Symphony is an autonomous coding agent orchestration service. It polls a Linear issue tracker,
creates isolated workspaces per issue, and runs Codex in app-server mode to complete tasks.

The repository contains:
- A language-agnostic spec (`SPEC.md`) teams can implement in any language.
- A reference Elixir/OTP implementation (`elixir/`).
- Repository-local Codex skills (`.codex/skills/`).

> Warning: Symphony is a low-key engineering preview for trusted environments. It is not
> production-hardened.

---

## Repository Layout

```
/
├── SPEC.md                      # Language-agnostic service specification (~80 KB)
├── README.md                    # Project overview and running instructions
├── elixir/                      # Reference Elixir/OTP implementation
│   ├── lib/
│   │   ├── symphony_elixir/     # Core orchestration logic
│   │   │   ├── orchestrator.ex      # Main polling/dispatch GenServer loop
│   │   │   ├── agent_runner.ex      # Per-issue Codex execution
│   │   │   ├── workspace.ex         # Workspace lifecycle (create/hooks/cleanup)
│   │   │   ├── codex/               # Codex app-server protocol
│   │   │   ├── linear/              # Linear GraphQL client and adapter
│   │   │   ├── config.ex            # Config accessors
│   │   │   ├── config/schema.ex     # Ecto-based config schema
│   │   │   ├── workflow.ex          # WORKFLOW.md loader
│   │   │   ├── prompt_builder.ex    # Liquid template rendering
│   │   │   ├── tracker.ex           # Tracker abstraction
│   │   │   └── tracker/memory.ex    # In-memory test tracker
│   │   └── symphony_elixir_web/ # Phoenix web UI (LiveView dashboard + JSON API)
│   ├── test/                    # ExUnit test suite
│   ├── config/                  # Phoenix config files
│   ├── docs/                    # Implementation docs (logging, token accounting)
│   ├── WORKFLOW.md              # In-repo workflow contract (YAML + prompt template)
│   ├── AGENTS.md                # Codebase conventions (source of truth for the elixir/ dir)
│   ├── mix.exs                  # Mix project definition + dependencies
│   ├── Makefile                 # Build targets
│   └── mise.toml                # Tool versions (erlang 28, elixir 1.19.5)
├── .codex/skills/               # Repository-local Codex skills
│   ├── commit/, push/, pull/, land/, debug/, linear/
│   └── worktree_init.sh
└── .github/
    ├── workflows/make-all.yml   # CI pipeline
    └── pull_request_template.md # PR body template
```

---

## Development Environment

**Toolchain**: Elixir 1.19.x on OTP 28, managed by [mise](https://mise.jdx.dev/).

```bash
# Install and verify toolchain
cd elixir
mise trust
mise install
mise exec -- elixir --version

# Install Mix dependencies
mix setup
```

All subsequent commands should be run from the `elixir/` directory.

---

## Common Commands

All work is done from `elixir/`. The `Makefile` wraps the most common Mix commands.

| Command | What it does |
|---|---|
| `make setup` | `mix setup` — install deps |
| `make build` | `mix escript.build` — build the `bin/symphony` binary |
| `make fmt` | Auto-format all source files |
| `make fmt-check` | Check formatting (CI gate) |
| `make lint` | `mix lint` — runs `specs.check` + `credo --strict` |
| `make test` | Run unit tests |
| `make coverage` | Run tests with coverage (100% required) |
| `make dialyzer` | Run Dialyzer type checking |
| `make e2e` | Live end-to-end test (requires `LINEAR_API_KEY`) |
| `make all` | Full CI gate: setup → build → fmt-check → lint → coverage → dialyzer |

**Always run `make all` before handing off a change.**

### Running Symphony

```bash
cd elixir
./bin/symphony ./WORKFLOW.md
# Optional flags:
#   --port <n>       Enable Phoenix dashboard and JSON API
#   --logs-root <p>  Write logs under a different directory (default: ./log)
```

---

## Configuration — WORKFLOW.md

Runtime configuration lives entirely in `WORKFLOW.md` (YAML front matter + Liquid prompt body).

Minimal example:

```markdown
---
tracker:
  kind: linear
  project_slug: "..."
workspace:
  root: ~/code/workspaces
hooks:
  after_create: |
    git clone git@github.com:your-org/your-repo.git .
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex app-server
---

You are working on Linear issue {{ issue.identifier }}.
Title: {{ issue.title }}
Body: {{ issue.description }}
```

Key rules:
- `tracker.api_key` reads from `$LINEAR_API_KEY` when unset.
- `workspace.root` expands `~` and `$VAR` before use.
- `codex.command` is a shell string; `$VAR` expansion happens in the launched shell.
- Missing fields fall back to safe defaults (see `elixir/README.md` for full defaults).
- If WORKFLOW.md is invalid at startup, Symphony will not boot.
- Hot reloads happen on file change; a failed reload keeps the last known-good config.

Config is loaded through `SymphonyElixir.Workflow` → `SymphonyElixir.Config`.
Add new config access via `SymphonyElixir.Config`, not ad-hoc env reads.

---

## Code Conventions

### Required: `@spec` on all public functions

Every `def` in `lib/` must have an adjacent `@spec`. `defp` specs are optional.
`@impl` callback implementations are exempt.

```bash
mix specs.check   # validates compliance
```

### Alignment with SPEC.md

- The Elixir implementation may be a **superset** of the spec.
- The implementation must **not conflict** with the spec.
- If a change meaningfully alters intended behavior, update `SPEC.md` in the same PR.

### Workspace safety

- Never run a Codex turn with `cwd` inside the source repository.
- Workspaces must stay under the configured `workspace_root` (enforced by `PathSafety`).

### Orchestrator / concurrency

The `Orchestrator` GenServer is stateful and concurrency-sensitive. Preserve:
- Retry and exponential backoff semantics.
- Reconciliation and cleanup on terminal issue states.
- Hot-reload behavior (WORKFLOW.md changes must not abort running agents).

### Logging

Follow `docs/logging.md`. Always include these context fields:

| Scope | Required fields |
|---|---|
| Issue-related work | `issue_id` (UUID), `issue_identifier` (e.g. `MT-620`) |
| Codex session events | `session_id` |

Use `key=value` pairs in message text for high-signal fields. Include the outcome
(`completed`, `failed`, `retrying`) and the error reason when relevant.

### Style

- Line length: 200 characters (`.formatter.exs`).
- Follow existing module patterns in `lib/symphony_elixir/*`.
- Keep changes narrowly scoped; avoid unrelated refactors.

---

## Testing

Tests live in `elixir/test/`. Use the `SymphonyElixir.TestSupport` mixin for shared setup.

```bash
# Targeted run while iterating:
mix test test/symphony_elixir/some_test.exs

# Full gate before handoff:
make all

# Live E2E (creates real Linear resources and runs real Codex):
export LINEAR_API_KEY=...
make e2e
```

100% coverage is enforced. Snapshot-based testing is used for complex state assertions
(`test/support/snapshot_support.exs`).

E2E environment variables:
- `SYMPHONY_LIVE_LINEAR_TEAM_KEY` — defaults to `SYME2E`
- `SYMPHONY_LIVE_SSH_WORKER_HOSTS` — comma-separated SSH hosts (uses Docker Compose if unset)

---

## Pull Request Requirements

PR body must exactly match `.github/pull_request_template.md`:

```markdown
#### Context
<!-- Why is this change needed? Length <= 240 chars -->

#### TL;DR
*<!-- Short description. Length <= 120 chars -->*

#### Summary
- <!-- Bullet points, high level, each <= 120 chars -->

#### Alternatives
- <!-- What was considered and why not used -->

#### Test Plan
- [ ] `make -C elixir all`
- [ ] <!-- Additional targeted checks -->
```

Validate locally before opening a PR:

```bash
mix pr_body.check --file /path/to/pr_body.md
```

---

## Documentation Update Policy

When behavior or config changes, update docs in the same PR:

| What changed | Doc to update |
|---|---|
| Project concept or goals | `README.md` |
| Elixir setup or run instructions | `elixir/README.md` |
| Workflow / config contract | `elixir/WORKFLOW.md` |
| Service behavior or spec | `SPEC.md` |

---

## CI

GitHub Actions runs `make all` on every PR and push to `main` via `.github/workflows/make-all.yml`.
A separate workflow (`.github/workflows/pr-description-lint.yml`) validates PR body format using
`mix pr_body.check`.

---

## Key Environment Variables

| Variable | Purpose |
|---|---|
| `LINEAR_API_KEY` | Linear personal API key (required) |
| `SYMPHONY_WORKSPACE_ROOT` | Optional base path for workspaces |
| `SYMPHONY_RUN_LIVE_E2E` | Set to `1` to enable live E2E tests |
| `SYMPHONY_LIVE_LINEAR_TEAM_KEY` | Override Linear team key in E2E (default: `SYME2E`) |
| `SYMPHONY_LIVE_SSH_WORKER_HOSTS` | Comma-separated SSH hosts for E2E |
