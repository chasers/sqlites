import Config

config :sqlites_operator,
  metadb: [
    hostname: System.get_env("METADB_HOST", "postgres"),
    username: System.get_env("METADB_USER", "postgres"),
    password: System.get_env("METADB_PASSWORD", "postgres"),
    database: System.get_env("METADB_DATABASE", "sqlites"),
    port: String.to_integer(System.get_env("METADB_PORT", "5432"))
  ]

config :sqlites_operator,
  auto_evacuate: [
    enabled: System.get_env("AUTO_EVACUATE", "true") in ~w(true 1),
    window_seconds: String.to_integer(System.get_env("AUTO_EVACUATE_WINDOW_SECONDS", "120"))
  ]
