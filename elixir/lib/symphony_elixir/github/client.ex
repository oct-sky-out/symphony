defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  GitHub REST API client for issue management.

  Talks to `https://api.github.com` using a personal access token or
  fine-grained token supplied via `tracker.api_key` (or the `GITHUB_TOKEN`
  environment variable).

  ## Required `tracker.extra_config` keys

  - `"owner"` — Repository owner (user or organisation login).
  - `"repo"`  — Repository name.

  ## Optional `tracker.extra_config` keys

  - `"labels"` — List of label names to filter candidate issues (default: `[]`).
  - `"assignee"` — Assignee login to filter issues (overrides `tracker.assignee`).

  ## State mapping

  GitHub issues only have two native states: `"open"` and `"closed"`.
  Configure `active_states: ["open"]` and `terminal_states: ["closed"]`
  for standard behaviour.  `update_issue_state/2` maps any configured
  state name to `"open"` or `"closed"` based on whether it appears in
  the configured `terminal_states`.
  """

  require Logger

  alias SymphonyElixir.{Config, Tracker.Issue}

  @base_url "https://api.github.com"
  @issues_per_page 100
  @max_error_body_log_bytes 1_000

  # ---------------------------------------------------------------------------
  # Public API (called by GitHub.Adapter)
  # ---------------------------------------------------------------------------

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    with {:ok, config} <- load_config() do
      do_fetch_open_issues(config, 1, [])
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    with {:ok, config} <- load_config() do
      # GitHub only supports "open" and "closed"; map configured state names.
      github_states =
        state_names
        |> Enum.map(&normalize_github_state/1)
        |> Enum.uniq()

      pages =
        Enum.map(github_states, fn github_state ->
          do_fetch_issues_by_github_state(config, github_state, 1, [])
        end)

      merge_results(pages)
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    with {:ok, config} <- load_config() do
      results =
        Enum.map(issue_ids, fn issue_number ->
          fetch_single_issue(config, issue_number)
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if errors == [] do
        issues =
          results
          |> Enum.flat_map(fn
            {:ok, nil} -> []
            {:ok, issue} -> [issue]
          end)

        {:ok, issues}
      else
        {:error, elem(hd(errors), 1)}
      end
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_number, body)
      when is_binary(issue_number) and is_binary(body) do
    with {:ok, config} <- load_config(),
         {:ok, headers} <- auth_headers(config),
         url = issue_url(config, issue_number) <> "/comments",
         {:ok, %{status: 201}} <-
           Req.post(url, headers: headers, json: %{"body" => body}, connect_options: [timeout: 30_000]) do
      :ok
    else
      {:ok, response} ->
        Logger.error("GitHub create comment failed status=#{response.status}#{github_error_context(response)}")
        {:error, {:github_api_status, response.status}}

      {:error, reason} ->
        Logger.error("GitHub create comment request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_number, state_name)
      when is_binary(issue_number) and is_binary(state_name) do
    with {:ok, config} <- load_config(),
         {:ok, headers} <- auth_headers(config) do
      github_state = terminal_state?(state_name, config) && "closed" || "open"
      url = issue_url(config, issue_number)

      case Req.patch(url, headers: headers, json: %{"state" => github_state}, connect_options: [timeout: 30_000]) do
        {:ok, %{status: status}} when status in [200, 201] ->
          :ok

        {:ok, response} ->
          Logger.error("GitHub update issue state failed status=#{response.status}#{github_error_context(response)}")
          {:error, {:github_api_status, response.status}}

        {:error, reason} ->
          Logger.error("GitHub update issue state request failed: #{inspect(reason)}")
          {:error, {:github_api_request, reason}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  @doc false
  @spec normalize_issue_for_test(map(), map()) :: Issue.t() | nil
  def normalize_issue_for_test(raw_issue, config) when is_map(raw_issue) and is_map(config) do
    normalize_issue(raw_issue, config)
  end

  # ---------------------------------------------------------------------------
  # Private — HTTP helpers
  # ---------------------------------------------------------------------------

  defp do_fetch_open_issues(config, page, acc) do
    params =
      [state: "open", per_page: @issues_per_page, page: page]
      |> maybe_add_labels(config)
      |> maybe_add_assignee(config)

    url = "#{@base_url}/repos/#{config.owner}/#{config.repo}/issues"

    case get_json(url, params, config) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc)}

      {:ok, issues} ->
        normalized = Enum.flat_map(issues, &List.wrap(normalize_issue(&1, config)))
        new_acc = Enum.reverse(normalized, acc)

        if length(issues) < @issues_per_page do
          {:ok, Enum.reverse(new_acc)}
        else
          do_fetch_open_issues(config, page + 1, new_acc)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fetch_issues_by_github_state(config, github_state, page, acc) do
    params = [state: github_state, per_page: @issues_per_page, page: page]
    url = "#{@base_url}/repos/#{config.owner}/#{config.repo}/issues"

    case get_json(url, params, config) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc)}

      {:ok, issues} ->
        normalized = Enum.flat_map(issues, &List.wrap(normalize_issue(&1, config)))
        new_acc = Enum.reverse(normalized, acc)

        if length(issues) < @issues_per_page do
          {:ok, Enum.reverse(new_acc)}
        else
          do_fetch_issues_by_github_state(config, github_state, page + 1, new_acc)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_single_issue(config, issue_number) do
    url = issue_url(config, issue_number)

    case get_json(url, [], config) do
      {:ok, %{} = raw_issue} ->
        {:ok, normalize_issue(raw_issue, config)}

      {:ok, _} ->
        {:ok, nil}

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_json(url, params, config) do
    with {:ok, headers} <- auth_headers(config) do
      query = URI.encode_query(params)
      full_url = if query == "", do: url, else: "#{url}?#{query}"

      case Req.get(full_url, headers: headers, connect_options: [timeout: 30_000]) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          Logger.error("GitHub API request failed status=#{response.status} url=#{url}#{github_error_context(response)}")
          {:error, {:github_api_status, response.status}}

        {:error, reason} ->
          Logger.error("GitHub API request failed: #{inspect(reason)}")
          {:error, {:github_api_request, reason}}
      end
    end
  end

  defp auth_headers(%{api_key: api_key}) when is_binary(api_key) do
    {:ok,
     [
       {"Authorization", "Bearer #{api_key}"},
       {"Accept", "application/vnd.github+json"},
       {"X-GitHub-Api-Version", "2022-11-28"}
     ]}
  end

  defp auth_headers(_config) do
    {:error, :missing_github_api_token}
  end

  defp issue_url(config, issue_number) do
    "#{@base_url}/repos/#{config.owner}/#{config.repo}/issues/#{issue_number}"
  end

  # ---------------------------------------------------------------------------
  # Private — issue normalization
  # ---------------------------------------------------------------------------

  defp normalize_issue(raw, config) when is_map(raw) do
    number = raw["number"]

    if is_integer(number) do
      %Issue{
        id: to_string(number),
        identifier: "##{number}",
        title: raw["title"],
        description: raw["body"],
        priority: nil,
        state: raw["state"],
        branch_name: nil,
        url: raw["html_url"],
        assignee_id: get_in(raw, ["assignee", "login"]),
        labels: extract_labels(raw),
        assigned_to_worker: assigned_to_worker?(raw, config),
        blocked_by: [],
        created_at: parse_datetime(raw["created_at"]),
        updated_at: parse_datetime(raw["updated_at"])
      }
    else
      nil
    end
  end

  defp normalize_issue(_raw, _config), do: nil

  defp extract_labels(%{"labels" => labels}) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> String.downcase(name)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_labels(_), do: []

  defp assigned_to_worker?(_raw, %{assignee: nil}), do: true

  defp assigned_to_worker?(raw, %{assignee: assignee}) when is_binary(assignee) do
    case get_in(raw, ["assignee", "login"]) do
      login when is_binary(login) -> String.downcase(login) == String.downcase(assignee)
      _ -> false
    end
  end

  defp assigned_to_worker?(_raw, _config), do: true

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  # ---------------------------------------------------------------------------
  # Private — config helpers
  # ---------------------------------------------------------------------------

  defp load_config do
    tracker = Config.settings!().tracker
    extra = tracker.extra_config || %{}

    owner = extra["owner"]
    repo = extra["repo"]

    cond do
      not is_binary(tracker.api_key) ->
        {:error, :missing_github_api_token}

      not is_binary(owner) ->
        {:error, :missing_github_owner}

      not is_binary(repo) ->
        {:error, :missing_github_repo}

      true ->
        {:ok,
         %{
           api_key: tracker.api_key,
           owner: owner,
           repo: repo,
           assignee: extra["assignee"] || tracker.assignee,
           labels: List.wrap(extra["labels"]),
           active_states: tracker.active_states,
           terminal_states: tracker.terminal_states
         }}
    end
  end

  defp maybe_add_labels(params, %{labels: [_ | _] = labels}) do
    Keyword.put(params, :labels, Enum.join(labels, ","))
  end

  defp maybe_add_labels(params, _config), do: params

  defp maybe_add_assignee(params, %{assignee: assignee}) when is_binary(assignee) do
    Keyword.put(params, :assignee, assignee)
  end

  defp maybe_add_assignee(params, _config), do: params

  defp terminal_state?(state_name, %{terminal_states: terminal_states}) do
    normalized = String.downcase(state_name)
    Enum.any?(terminal_states, &(String.downcase(&1) == normalized))
  end

  defp normalize_github_state(state_name) do
    # Map configured state names (which may vary) back to GitHub's "open"/"closed".
    # Any non-"closed" variant maps to "open".
    case String.downcase(state_name) do
      "closed" -> "closed"
      _ -> "open"
    end
  end

  defp merge_results(results) do
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      issues =
        results
        |> Enum.flat_map(fn {:ok, list} -> list end)
        |> Enum.uniq_by(& &1.id)

      {:ok, issues}
    else
      {:error, elem(hd(errors), 1)}
    end
  end

  defp github_error_context(response) do
    body =
      response
      |> Map.get(:body)
      |> summarize_body()

    " body=#{body}"
  end

  defp summarize_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> then(fn b ->
      if byte_size(b) > @max_error_body_log_bytes do
        binary_part(b, 0, @max_error_body_log_bytes) <> "...<truncated>"
      else
        b
      end
    end)
    |> inspect()
  end

  defp summarize_body(body), do: inspect(body, limit: 20, printable_limit: @max_error_body_log_bytes)
end
