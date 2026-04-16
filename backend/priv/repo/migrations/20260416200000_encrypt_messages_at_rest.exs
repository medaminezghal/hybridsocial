defmodule Hybridsocial.Repo.Migrations.EncryptMessagesAtRest do
  use Ecto.Migration

  def up do
    # Per user decision: drop all existing DM content (pre-launch).
    # FKs with on_delete: :delete_all handle message_reactions and
    # delivery_statuses cascades automatically when messages go.
    execute("DELETE FROM message_reactions")
    execute("DELETE FROM message_delivery_status")
    execute("DELETE FROM messages")

    alter table(:messages) do
      # Plaintext is now nullable; populated only for encryption_version = 0
      # (legacy rows, which we just deleted — but keeping the column means a
      # future federated import of unencrypted messages still works).
      modify :content, :text, null: true, from: :string

      add :ciphertext, :binary
      add :nonce, :binary
      add :encryption_version, :integer, null: false, default: 0
    end
  end

  def down do
    alter table(:messages) do
      remove :encryption_version
      remove :nonce
      remove :ciphertext
      modify :content, :string, null: false, from: :text
    end
  end
end
