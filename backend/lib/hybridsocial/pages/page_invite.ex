defmodule Hybridsocial.Pages.PageInvite do
  @moduledoc """
  Invitation from an existing page manager to another identity,
  offering them a manager role on the page. Mirrors the
  `Groups.GroupInvite` schema so the two invite flows stay parallel.

  `page_id` points at the page identity (pages are a subaccount
  type; they're rows in `identities`). `invited_by` is the manager
  sending the invite, `invited_id` is the recipient.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "page_invites" do
    field :status, :string, default: "pending"

    belongs_to :page, Hybridsocial.Accounts.Identity
    belongs_to :inviter, Hybridsocial.Accounts.Identity, foreign_key: :invited_by
    belongs_to :invited, Hybridsocial.Accounts.Identity, foreign_key: :invited_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:page_id, :invited_by, :invited_id, :status])
    |> validate_required([:page_id, :invited_by, :invited_id])
    |> validate_inclusion(:status, ~w(pending accepted declined))
    |> foreign_key_constraint(:page_id)
    |> foreign_key_constraint(:invited_by)
    |> foreign_key_constraint(:invited_id)
    |> unique_constraint([:page_id, :invited_id])
  end
end
