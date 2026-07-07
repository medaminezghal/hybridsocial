defmodule Mix.Tasks.Hybridsocial.Backfill.RemoteEmojis do
  @moduledoc """
  One-off backfill (dev/mix convenience): re-fetch every remote actor and
  repopulate the `emojis` + `profile_url` columns added after those actors
  were first federated. In production (a release) run the shared
  implementation directly instead:

      bin/hybridsocial rpc "Hybridsocial.Release.backfill_remote_emojis()"

  Usage:

      mix hybridsocial.backfill.remote_emojis          # only rows missing data
      mix hybridsocial.backfill.remote_emojis --all     # every remote identity
  """
  use Mix.Task

  @shortdoc "Re-fetch remote actors to backfill emojis + profile URLs"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Hybridsocial.Release.backfill_remote_emojis(all: "--all" in args)
  end
end
