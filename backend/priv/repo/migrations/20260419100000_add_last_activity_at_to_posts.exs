defmodule Hybridsocial.Repo.Migrations.AddLastActivityAtToPosts do
  use Ecto.Migration

  @moduledoc """
  Thread-bumping: ordering Explore / global timelines by
  `last_activity_at` floats threads with new replies back to the top,
  same way forums and Twitter handle it. The column is denormalized
  (cheap read, one extra UPDATE on reply insert) rather than a
  subquery per timeline read.

  Backfill sets it to the greater of the post's own `published_at`
  and the most recent published reply's `published_at` (via
  `root_id`), so existing threads get one consistent initial value
  instead of everyone having to wait for a new reply before they
  surface correctly.
  """

  def change do
    alter table(:posts) do
      add :last_activity_at, :utc_datetime_usec
    end

    # Index matches the timeline query's sort order exactly. DESC so
    # the scan can walk the index in order; Postgres will use it for
    # `ORDER BY last_activity_at DESC LIMIT N`.
    create index(:posts, ["last_activity_at DESC"])

    # Backfill. Two passes because a single UPDATE … FROM can't
    # reference the aggregated subquery inline on every Postgres
    # version cleanly, and the correctness cost isn't worth it.
    execute(
      """
      UPDATE posts SET last_activity_at = published_at WHERE last_activity_at IS NULL
      """,
      """
      UPDATE posts SET last_activity_at = NULL
      """
    )

    # Then walk each root's replies and promote the latest published_at.
    # Only applied forward — the down migration just clears the column.
    execute(
      """
      UPDATE posts p SET last_activity_at = latest.ts
      FROM (
        SELECT root_id, MAX(published_at) AS ts
        FROM posts
        WHERE root_id IS NOT NULL
          AND deleted_at IS NULL
          AND published_at IS NOT NULL
        GROUP BY root_id
      ) latest
      WHERE p.id = latest.root_id
        AND (p.last_activity_at IS NULL OR p.last_activity_at < latest.ts)
      """,
      ""
    )
  end
end
