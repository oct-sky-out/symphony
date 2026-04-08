defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for issue tracker reads, writes, and agent-facing tools.

  ## Implementing a new tracker adapter

  Create a module that `@behaviour SymphonyElixir.Tracker` and implement every
  callback listed below.  Then register the adapter by setting `tracker.kind`
  in your `WORKFLOW.md` to any string and adding a clause to `adapter/0` that
  maps that string to your new module.

  ### Required callbacks

  | Callback | Description |
  |---|---|
  | `fetch_candidate_issues/0` | Poll for issues ready to be worked on |
  | `fetch_issues_by_states/1` | Fetch issues whose state names match the list |
  | `fetch_issue_states_by_ids/1` | Fetch only the current state for a set of issue IDs |
  | `create_comment/2` | Append a comment to an issue |
  | `update_issue_state/2` | Transition an issue to a new named state |
  | `tool_specs/0` | Return JSON-Schema tool descriptors exposed to the Codex agent |
  | `execute_tool/2` | Execute a tracker-specific tool call from the agent |

  ### `tool_specs/0` and `execute_tool/2`

  These two callbacks let each adapter expose arbitrary tools to the running
  Codex agent.  `tool_specs/0` returns a list of tool descriptor maps (same
  format as Codex tool definitions).  When the agent calls one of those tools,
  `execute_tool/2` receives the tool name and raw arguments and must return a
  response map with at least `"success"`, `"output"`, and `"contentItems"` keys.

  Adapters that do not need to expose any extra tools to agents should return
  `[]` from `tool_specs/0` and an error map from `execute_tool/2`.
  """

  alias SymphonyElixir.Config

  @callback fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}

  @doc """
  Returns the list of tool descriptors (JSON-Schema format) that this adapter
  wishes to expose to the Codex agent during a session.
  """
  @callback tool_specs() :: [map()]

  @doc """
  Executes a tracker-specific tool call requested by the Codex agent.

  `tool_name` is one of the names returned by `tool_specs/0`.  `arguments` is
  the raw arguments map (or string) sent by the agent.  `opts` is an optional
  keyword list used primarily for test-time dependency injection (e.g. a mock
  HTTP client).  Production callers pass `[]`.

  Must return a response map with `"success"` (boolean), `"output"` (string),
  and `"contentItems"` (list) keys — the same shape used by `DynamicTool`.
  """
  @callback execute_tool(tool_name :: String.t(), arguments :: term(), opts :: keyword()) :: map()

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    adapter().fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    adapter().fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    adapter().fetch_issue_states_by_ids(issue_ids)
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    adapter().create_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    adapter().update_issue_state(issue_id, state_name)
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    adapter().tool_specs()
  end

  @spec execute_tool(String.t(), term(), keyword()) :: map()
  def execute_tool(tool_name, arguments, opts \\ []) do
    adapter().execute_tool(tool_name, arguments, opts)
  end

  @doc """
  Returns the adapter module configured by `tracker.kind` in `WORKFLOW.md`.

  To add support for a new tracker, add a clause here mapping its `kind` string
  to the adapter module, and add the same string to `registered_kinds/0`.
  """
  @spec adapter() :: module()
  def adapter do
    case Config.settings!().tracker.kind do
      "memory" -> SymphonyElixir.Tracker.Memory
      "linear" -> SymphonyElixir.Linear.Adapter
      _ -> SymphonyElixir.Linear.Adapter
    end
  end

  @doc """
  Returns the list of tracker kind strings that have a registered adapter.

  Used by `SymphonyElixir.Config` to validate `tracker.kind` in `WORKFLOW.md`.
  When adding a new adapter, add its kind string here as well as a clause in
  `adapter/0`.
  """
  @spec registered_kinds() :: [String.t()]
  def registered_kinds, do: ["linear", "memory"]
end
