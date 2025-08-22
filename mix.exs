defmodule AgentCoordinator.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_coordinator,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AgentCoordinator.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:gnat, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.1"},
      {:gen_stage, "~> 1.2"},
      {:uuid, "~> 1.1"}
    ]
  end
end
