defmodule Gnat.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gnat,
      version: "0.1.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),

      name: "Gnat",
      source_url: "",
      homepage_url: "",
      docs: [
        main: "README",
        extras: ["README.md": [title: "README"]]
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:exprotobuf, "~> 1.2"},
      {:connection, "~> 1.0"},
      {:poison, "~> 3.0"},
      {:secure_random, "~> 0.5.0"},
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end

end
