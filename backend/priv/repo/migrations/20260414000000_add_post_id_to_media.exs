defmodule Hybridsocial.Repo.Migrations.AddPostIdToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :post_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:media, [:post_id])
  end
end
