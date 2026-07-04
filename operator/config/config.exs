import Config

config :sqlites_operator,
  env: config_env(),
  start_operator: config_env() == :prod

config :bonny,
  get_conn: {SqlitesOperator.K8sConn, :get!, [config_env()]},
  service_account_name: "sqlites-operator",
  labels: %{"k8s-app" => "sqlites-operator"},
  operator_name: "sqlites-operator",
  namespace: "sqlites"
