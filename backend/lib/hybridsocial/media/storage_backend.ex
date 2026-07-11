defmodule Hybridsocial.Media.StorageBackend do
  @moduledoc """
  Behaviour for media storage backends.

  Each backend must implement `store/2`, `delete/1`, `exists?/1`, `url/1`, and `name/0`.
  Backends are resolved at runtime via `Hybridsocial.Media.StorageResolver`.
  """

  @doc "Store an upload and return `{:ok, storage_path}` on success."
  @callback store(upload :: Plug.Upload.t(), identity_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Delete a previously stored file by its storage path."
  @callback delete(storage_path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Check whether a stored object still exists.

  Returns `{:ok, true}` / `{:ok, false}` for a definitive answer, or
  `{:error, reason}` when the backend couldn't be reached (transient
  network/permission failure). Callers must treat `{:error, _}` as
  "unknown" and never as "missing" — it's used to decide destructive
  cleanup.
  """
  @callback exists?(storage_path :: String.t()) :: {:ok, boolean()} | {:error, term()}

  @doc "Return the public URL for the given storage path."
  @callback url(storage_path :: String.t()) :: String.t()

  @doc "Return a human-readable name for this backend (e.g. `\"local\"`)."
  @callback name() :: String.t()
end
