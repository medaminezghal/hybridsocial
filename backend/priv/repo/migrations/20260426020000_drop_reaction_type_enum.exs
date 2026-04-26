defmodule Hybridsocial.Repo.Migrations.DropReactionTypeEnum do
  use Ecto.Migration

  # The `reaction_type` enum was originally locked to the 7 default
  # reactions ('like', 'love', 'care', 'angry', 'sad', 'lol', 'wow').
  # Premium reactions are admin-curated bare shortcodes like "fire" —
  # any insert with a non-enum value 500s with
  # `invalid_input_value for enum reaction_type`.
  #
  # Move the column to plain text. Application-side validation in
  # `Reaction.changeset` already constrains it (regex + standard
  # set + premium catalog lookup), so the DB enum is redundant and
  # actively blocks the premium feature.
  def up do
    execute "ALTER TABLE reactions ALTER COLUMN type TYPE text USING type::text"
    execute "DROP TYPE reaction_type"
  end

  def down do
    execute "CREATE TYPE reaction_type AS ENUM ('like', 'love', 'care', 'angry', 'sad', 'lol', 'wow')"

    execute "ALTER TABLE reactions ALTER COLUMN type TYPE reaction_type USING type::reaction_type"
  end
end
