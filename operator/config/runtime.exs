import Config

config :sqlites_operator,
  metadb: [
    hostname: System.get_env("METADB_HOST", "postgres"),
    username: System.get_env("METADB_USER", "postgres"),
    password: System.get_env("METADB_PASSWORD", "postgres"),
    database: System.get_env("METADB_DATABASE", "sqlites"),
    port: String.to_integer(System.get_env("METADB_PORT", "5432"))
  ]
