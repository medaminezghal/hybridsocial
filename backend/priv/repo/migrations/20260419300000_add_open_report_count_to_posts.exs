defmodule Hybridsocial.Repo.Migrations.AddOpenReportCountToPosts do
  use Ecto.Migration

  @moduledoc """
  Denormalized open-report count on posts, so the admin moderation
  shield can display a "there are N pending reports on this post"
  badge without a per-post JOIN on every timeline fetch.

  Kept in sync by Moderation context:
    * create_report (target_type="post")           → +1
    * resolve_report / dismiss_report on a post    → −1 (clamped to 0)

  Backfill counts current pending reports per post so the first
  render after deploy reflects reality.
  """

  def change do
    alter table(:posts) do
      add :open_report_count, :integer, default: 0, null: false
    end

    execute(
      """
      UPDATE posts p
      SET open_report_count = coalesce(sub.cnt, 0)
      FROM (
        SELECT target_id::uuid AS pid, COUNT(*) AS cnt
        FROM reports
        WHERE target_type = 'post' AND status = 'pending'
        GROUP BY target_id
      ) sub
      WHERE p.id = sub.pid
      """,
      "UPDATE posts SET open_report_count = 0"
    )
  end
end
