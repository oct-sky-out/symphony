defmodule SymphonyElixir.Linear.Issue do
  @moduledoc """
  Backward-compatibility shim — use `SymphonyElixir.Issue` directly instead.

  The canonical issue struct has moved to `SymphonyElixir.Issue` so that it can
  be shared across all tracker adapters without a Linear-specific namespace.
  This module re-exports the type so that any external code still referencing
  `SymphonyElixir.Linear.Issue` continues to compile.
  """

  @type t :: SymphonyElixir.Issue.t()
end
