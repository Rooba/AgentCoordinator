defmodule AgentCoordinatorTest do
  use ExUnit.Case
  doctest AgentCoordinator

  test "greets the world" do
    assert AgentCoordinator.hello() == :world
  end
end
