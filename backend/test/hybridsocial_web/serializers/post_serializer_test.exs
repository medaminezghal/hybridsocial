defmodule HybridsocialWeb.Serializers.PostSerializerTest do
  @moduledoc """
  Unit tests for PostSerializer's account block — specifically the
  verification fields that the frontend badge UI keys off.
  """
  use Hybridsocial.DataCase, async: true

  alias HybridsocialWeb.Serializers.PostSerializer

  defp identity(attrs) do
    base = %Hybridsocial.Accounts.Identity{
      id: Ecto.UUID.generate(),
      type: "user",
      handle: "alice",
      display_name: "Alice",
      inserted_at: ~U[2026-01-01 00:00:00.000000Z]
    }

    Map.merge(base, attrs)
  end

  describe "serialize_account/2 verification fields" do
    test "includes verification_tier and is_verified=true for paid tiers" do
      for tier <- ["verified_starter", "verified_creator", "verified_pro"] do
        account = PostSerializer.serialize_account(identity(%{verification_tier: tier}), [])

        assert account.verification_tier == tier
        assert account.is_verified == true
      end
    end

    test "is_verified=false for the free tier" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "free"}), [])

      assert account.verification_tier == "free"
      assert account.is_verified == false
    end

    test "is_verified=false when verification_tier is nil" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: nil}), [])

      assert account.verification_tier == nil
      assert account.is_verified == false
    end

    test "is_verified=false for unknown tier strings" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "garbage"}), [])

      assert account.is_verified == false
    end
  end
end
