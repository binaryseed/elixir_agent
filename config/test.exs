use Mix.Config

config :logger, level: :warn

config :new_relic_agent,
  app_name: "ElixirAgentTest",
  automatic_attributes: [test_attribute: "test_value"],
  log: "memory"
