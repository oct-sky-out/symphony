defmodule SymphonyElixir.Linear.Issue do
  @moduledoc """
  Compatibility alias for `SymphonyElixir.Tracker.Issue`.

  The canonical issue struct now lives at `SymphonyElixir.Tracker.Issue`
  to support multiple tracker backends. This module is kept for backward
  compatibility.

  Use `SymphonyElixir.Tracker.Issue` in new code.
  """

  @type t :: SymphonyElixir.Tracker.Issue.t()
end
