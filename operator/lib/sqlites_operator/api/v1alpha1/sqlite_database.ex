defmodule SqlitesOperator.API.V1Alpha1.SqliteDatabase do
  @moduledoc """
  v1alpha1 of the SqliteDatabase custom resource.

  The control plane creates one of these per tenant database. The spec
  is the control plane's requests (placement, backup, restore); the
  status is the operator's report back (backups taken, restore state).
  """

  use Bonny.API.Version, hub: true

  @impl true
  def manifest do
    defaults()
    |> struct!(
      schema: %{
        openAPIV3Schema: %{
          type: :object,
          properties: %{
            spec: %{
              type: :object,
              required: ["databaseId", "tenantId"],
              properties: %{
                databaseId: %{type: :string},
                tenantId: %{type: :string},
                node: %{type: :string, nullable: true},
                backup: %{
                  type: :object,
                  nullable: true,
                  properties: %{
                    requestedAt: %{type: :string, format: :"date-time"}
                  }
                },
                restore: %{
                  type: :object,
                  nullable: true,
                  properties: %{
                    backupId: %{type: :string}
                  }
                }
              }
            },
            status: %{
              type: :object,
              nullable: true,
              properties: %{
                backups: %{
                  type: :array,
                  items: %{
                    type: :object,
                    properties: %{
                      id: %{type: :string},
                      completedAt: %{type: :string, format: :"date-time"},
                      sizeBytes: %{type: :integer}
                    }
                  }
                }
              },
              "x-kubernetes-preserve-unknown-fields": true
            }
          }
        }
      },
      additionalPrinterColumns: [
        %{name: "Database", type: :string, jsonPath: ".spec.databaseId"},
        %{name: "Tenant", type: :string, jsonPath: ".spec.tenantId"},
        %{name: "Node", type: :string, jsonPath: ".spec.node"}
      ],
      subresources: %{status: %{}}
    )
    |> add_observed_generation_status()
    |> add_conditions()
  end
end
