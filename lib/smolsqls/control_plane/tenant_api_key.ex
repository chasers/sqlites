defmodule Smolsqls.ControlPlane.TenantApiKey do
  @moduledoc """
  A permanent management API key for one tenant, managed exactly like
  database tokens: create (optionally with an expiration), disable,
  delete. The last usable key of a tenant cannot be disabled or
  deleted — that would be an unrecoverable lockout.

  The secret is stored hashed (auth lookup) plus encrypted (explicit
  reveal), never plaintext — see `Smolsqls.Secrets`. The virtual
  `token` field carries the plaintext only on create and reveal.
  """

  use Ecto.Schema

  alias Smolsqls.ControlPlane.SecretToken

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tenant_api_keys" do
    field :token, :string, virtual: true, redact: true
    field :token_hash, :string, redact: true
    field :token_ciphertext, :binary, redact: true
    field :name, :string
    field :enabled, :boolean, default: true
    field :expires_at, :utc_datetime_usec

    belongs_to :tenant, Smolsqls.ControlPlane.Tenant

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(api_key, attrs) do
    SecretToken.create_changeset(api_key, attrs, generate())
  end

  defdelegate update_changeset(api_key, attrs), to: SecretToken

  def generate do
    "sk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
