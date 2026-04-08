defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub Issues tracker adapter.

  Implements the `SymphonyElixir.Tracker` behaviour using the GitHub REST API.
  Configure with `tracker.kind: github` and the required `extra_config` keys:

  ```yaml
  tracker:
    kind: github
    api_key: $GITHUB_TOKEN          # or set GITHUB_TOKEN env var
    active_states: ["open"]
    terminal_states: ["closed"]
    extra_config:
      owner: "myorg"
      repo:  "myrepo"
      labels: []                    # optional — filter by labels
  ```

  See `SymphonyElixir.GitHub.Client` for full configuration reference.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.Client

  @spec fetch_candidate_issues() :: {:ok, [SymphonyElixir.Tracker.Issue.t()]} | {:error, term()}
  def fetch_candidate_issues, do: client_module().fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) ::
          {:ok, [SymphonyElixir.Tracker.Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states), do: client_module().fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) ::
          {:ok, [SymphonyElixir.Tracker.Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: client_module().fetch_issue_states_by_ids(issue_ids)

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body)
      when is_binary(issue_id) and is_binary(body) do
    client_module().create_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    client_module().update_issue_state(issue_id, state_name)
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :github_client_module, Client)
  end
end
