defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for issue tracker reads and writes.

  ## Adding a new tracker

  Implement the `SymphonyElixir.Tracker` behaviour in a new adapter module and
  register the `kind` string in `adapter/0`. Each callback must normalize native
  tracker data into `SymphonyElixir.Tracker.Issue` structs.

  Built-in adapters:

  | `kind`     | Module                             |
  |------------|------------------------------------|
  | `"linear"` | `SymphonyElixir.Linear.Adapter`    |
  | `"github"` | `SymphonyElixir.GitHub.Adapter`    |
  | `"memory"` | `SymphonyElixir.Tracker.Memory`    |
  """

  alias SymphonyElixir.{Config, Tracker.Issue}

  @callback fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}

  @adapters %{
    "linear" => SymphonyElixir.Linear.Adapter,
    "github" => SymphonyElixir.GitHub.Adapter,
    "memory" => SymphonyElixir.Tracker.Memory
  }

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    adapter().fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    adapter().fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
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

  @doc """
  Returns the adapter module for the configured tracker kind.

  Looks up the kind in the built-in adapter registry. If no match is found,
  falls back to `extra_config.module` for custom adapter modules.
  """
  @spec adapter() :: module()
  def adapter do
    kind = Config.settings!().tracker.kind

    case Map.get(@adapters, kind) do
      nil -> custom_adapter_module(kind)
      module -> module
    end
  end

  defp custom_adapter_module(kind) do
    case Config.settings!().tracker.extra_config do
      %{"module" => module_name} when is_binary(module_name) ->
        String.to_existing_atom("Elixir.#{module_name}")

      _ ->
        raise ArgumentError, "Unsupported tracker kind: #{inspect(kind)}. " <>
          "Set tracker.extra_config.module to a custom adapter module name."
    end
  end
end
