[
  parallel: true,
  skipped: true,
  tools: [
    {:compiler, "mix compile --warnings-as-errors --force"},
    {:credo, "mix credo --strict"},
    {:doctor, "mix doctor --raise"},
    {:ex_doc, "mix docs --warnings-as-errors"},
    {:ex_unit, "mix test --warnings-as-errors --cover", env: %{"MIX_ENV" => "test"}}
  ]
]
