defmodule SymphonyElixir.Tracker.Issue do
  @moduledoc """
  Normalized issue representation shared by all tracker adapters.

  Every tracker adapter (Linear, GitHub, Jira, etc.) must normalize
  its native issue format into this struct before returning it to the
  orchestrator. This decouples the orchestrator from tracker-specific
  data shapes.

  ## Fields

  - `id` — Stable opaque identifier used for writes and lookups (e.g. Linear UUID, GitHub issue number as string).
  - `identifier` — Human-readable issue key shown in logs and dashboards (e.g. `MT-123`, `#42`).
  - `title` — Issue title.
  - `description` — Issue body / description text.
  - `priority` — Integer priority; lower values sort first. `nil` ranks last.
  - `state` — Current state name as a string (e.g. `"In Progress"`, `"open"`).
  - `branch_name` — Optional VCS branch name associated with the issue.
  - `url` — Web URL for the issue in the tracker UI.
  - `assignee_id` — Tracker-native assignee identifier (user ID, login, etc.).
  - `labels` — List of lowercase label names.
  - `assigned_to_worker` — `true` when this issue should be processed by the current Symphony worker.
  - `blocked_by` — Issues that block this one from being dispatched.
  - `created_at` — Creation timestamp.
  - `updated_at` — Last-updated timestamp.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :assignee_id,
    blocked_by: [],
    labels: [],
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          labels: [String.t()],
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}) do
    labels
  end
end
