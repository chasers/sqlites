import Config

config :smolsqls_operator,
  env: config_env(),
  start_operator: config_env() == :prod

config :bonny,
  get_conn: {SmolsqlsOperator.K8sConn, :get!, [config_env()]},
  service_account_name: "smolsqls-operator",
  labels: %{"k8s-app" => "smolsqls-operator"},
  operator_name: "smolsqls-operator",
  namespace: "smolsqls"
