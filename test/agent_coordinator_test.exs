defmodule AgentCoordinatorTest do
  use ExUnit.Case
  doctest AgentCoordinator

  test "returns version" do
    assert is_binary(AgentCoordinator.version())
    assert AgentCoordinator.version() == "0.1.0"
  end

  test "returns status structure" do
    status = AgentCoordinator.status()
    assert is_map(status)
    assert Map.has_key?(status, :agents)
    assert Map.has_key?(status, :uptime)
  end
end
