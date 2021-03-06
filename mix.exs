defmodule FunnelHttp.Mixfile do
  use Mix.Project

  def project do
    [app: :funnel_http,
     version: "0.0.1",
     elixir: "~> 1.0.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:cowboy, :plug, :funnel, :logger],
     mod: {FunnelHttp, []}]
  end

  defp deps do
    [
      {:cowboy,               "~> 1.0"},
      {:plug,                 "~> 0.5"},
      {:funnel,               "~> 0.1"},
      {:event_source_encoder, "~> 0.0.1"}
    ]
  end
end
