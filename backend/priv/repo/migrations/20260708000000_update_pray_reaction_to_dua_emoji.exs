defmodule Hybridsocial.Repo.Migrations.UpdatePrayReactionToDuaEmoji do
  use Ecto.Migration

  @moduledoc """
  PR #1 changed the default "pray" premium reaction from 🙏 to 🤲 by
  editing the original seed migration (20260425200000). Editing an
  already-run migration only affects FRESH installs — on existing
  databases that seed already ran, so their `pray` row still holds 🙏 and
  the edit does nothing. This backfills those existing rows.

  Scoped to `character = '🙏'` so an operator who deliberately customized
  the pray reaction to some other glyph keeps their choice — the same
  conservative spirit as the original idempotent seed. That also makes it
  a no-op on fresh installs (already 🤲) and idempotent on re-run.
  """

  def up do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()

    execute("""
    UPDATE premium_reaction_emojis
       SET character = '🤲', updated_at = '#{now}'
     WHERE shortcode = 'pray' AND character = '🙏'
    """)
  end

  def down do
    # Mirror the sibling seed migration: don't auto-revert on rollback.
    # Operators may have re-touched the row, and rollbacks of a one-way
    # data fix are inherently lossy — safer to leave the value in place.
    :ok
  end
end
