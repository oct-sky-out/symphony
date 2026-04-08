defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Dispatches client-side tool calls requested by Codex app-server turns to the
  active tracker adapter.

  Each tracker adapter (e.g. `SymphonyElixir.Linear.Adapter`) declares its own
  set of agent-facing tools via `tool_specs/0` and handles execution via
  `execute_tool/2`.  This module is the single bridge between the Codex
  app-server protocol and those adapter callbacks.
  """

  alias SymphonyElixir.Tracker

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    Tracker.execute_tool(tool, arguments, opts)
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    Tracker.tool_specs()
  end
end
