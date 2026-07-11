defmodule Smolsqls.ControlPlane.SecretToken do
  @moduledoc """
  Shared changeset logic for the secret-bearing token schemas
  `Smolsqls.ControlPlane.DatabaseToken` and
  `Smolsqls.ControlPlane.TenantApiKey`. Both carry a plaintext secret only
  on create (stored hashed for lookup plus encrypted for reveal, per
  `Smolsqls.Secrets`), an optional future `expires_at`, and an `enabled`
  flag; they differ only in their parent association and secret prefix, so
  each schema owns its `generate/0` and hands the secret to
  `create_changeset/3`.
  """

  import Ecto.Changeset

  alias Smolsqls.Secrets

  @spec create_changeset(struct(), map(), String.t()) :: Ecto.Changeset.t()
  def create_changeset(token, attrs, secret) do
    token
    |> cast(attrs, [:name, :expires_at])
    |> put_change(:token, secret)
    |> put_change(:token_hash, Secrets.hash(secret))
    |> put_change(:token_ciphertext, Secrets.encrypt(secret))
    |> validate_expires_in_future()
  end

  @spec update_changeset(struct(), map()) :: Ecto.Changeset.t()
  def update_changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:enabled])
  end

  defp validate_expires_in_future(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        changeset

      expires_at ->
        if DateTime.after?(expires_at, DateTime.utc_now()) do
          changeset
        else
          add_error(changeset, :expires_at, "must be in the future")
        end
    end
  end
end
