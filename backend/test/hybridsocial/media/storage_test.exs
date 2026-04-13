defmodule Hybridsocial.Media.StorageTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Media.Storage

  # Track files we create so on_exit can clean up just those — never
  # rm_rf the uploads dir (parallel tests + real dev data both suffer).
  defp make_upload(content, content_type, ext) do
    tmp_path =
      Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.#{ext}")

    File.write!(tmp_path, content)

    on_exit(fn -> File.rm(tmp_path) end)

    %Plug.Upload{path: tmp_path, content_type: content_type, filename: "test.#{ext}"}
  end

  defp cleanup_storage(storage_path) do
    on_exit(fn -> Storage.delete(storage_path) end)
  end

  # ---------------------------------------------------------------------------
  # Local Storage (via the public Storage API)
  # ---------------------------------------------------------------------------

  describe "store/2" do
    test "stores a file and returns the relative path" do
      upload = make_upload("test content", "image/png", "png")

      assert {:ok, storage_path} = Storage.store(upload, "some-identity-id")
      cleanup_storage(storage_path)

      assert String.starts_with?(storage_path, "images/")
      assert String.ends_with?(storage_path, ".png")

      full = Path.join(Storage.uploads_dir(), storage_path)
      assert File.exists?(full)
      assert File.read!(full) == "test content"
    end

    test "routes video uploads under the videos/ prefix" do
      upload = make_upload("video content", "video/mp4", "mp4")

      assert {:ok, storage_path} = Storage.store(upload, "some-identity-id")
      cleanup_storage(storage_path)

      assert String.starts_with?(storage_path, "videos/")
      assert String.ends_with?(storage_path, ".mp4")
    end
  end

  describe "delete/1" do
    test "deletes a stored file" do
      upload = make_upload("test content", "image/jpeg", "jpg")
      {:ok, storage_path} = Storage.store(upload, "some-identity-id")

      full = Path.join(Storage.uploads_dir(), storage_path)
      assert File.exists?(full)

      assert :ok = Storage.delete(storage_path)
      refute File.exists?(full)
    end

    test "returns :ok when file does not exist" do
      assert :ok = Storage.delete("nonexistent/path.jpg")
    end
  end

  # ---------------------------------------------------------------------------
  # URL generation
  # ---------------------------------------------------------------------------

  describe "url/1" do
    test "returns URL with /uploads/ prefix for local storage" do
      url = Storage.url("images/2026/03/test.png")
      assert url =~ "/uploads/images/2026/03/test.png"
    end
  end

  # ---------------------------------------------------------------------------
  # Storage backend
  # ---------------------------------------------------------------------------

  describe "storage_backend/0" do
    test "defaults to local" do
      assert Storage.storage_backend() == "local"
    end
  end
end
