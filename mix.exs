defmodule Pmaker.Mixfile do
  use Mix.Project

  def project do
    [app: :pmaker,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [
						:logger,
						:silverb,
						:jazz,
						:mimetypes,
						:cowboy,
						:bullet,
					],
     mod: {Pmaker, []}]
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
			{:silverb, github: "timCF/silverb"},
			{:jazz, github: "meh/jazz"},
			{:mimetypes, github: "spawngrid/mimetypes"},
			{:cowboy, github: "ninenines/cowboy", tag: "0.9.0", override: true},
			{:bullet, github: "timCF/bullet", override: true},
		]
	end
end
