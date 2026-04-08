defmodule SymphonyElixir.Issue do
  @moduledoc """
  Normalized issue representation shared across all tracker adapters.

  Every tracker adapter (Linear, GitHub, Jira, Notion, etc.) is responsible for
  mapping its own API response into this struct before returning it to the
  orchestrator.  Fields that a given tracker does not support should be left as
  `nil` or their default value.
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
          # Tracker-internal unique identifier (opaque string).
          id: String.t() | nil,
          # Human-readable reference shown in UIs, e.g. "PROJ-123" or "#42".
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          # Numeric priority; lower values typically mean higher priority.
          priority: integer() | nil,
          # Current workflow state name (e.g. "Todo", "In Progress", "Done").
          state: String.t() | nil,
          # Suggested git branch name derived from the issue, if provided by the tracker.
          branch_name: String.t() | nil,
          # URL to view the issue in the tracker's web UI.
          url: String.t() | nil,
          # Tracker-internal ID of the assignee.
          assignee_id: String.t() | nil,
          # List of label names attached to the issue.
          labels: [String.t()],
          # true when the issue is assigned to the configured worker/bot account.
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}), do: labels
end
