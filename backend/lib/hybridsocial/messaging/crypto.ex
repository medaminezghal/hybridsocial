defmodule Hybridsocial.Messaging.Crypto do
  @moduledoc """
  At-rest encryption for direct message content.

  Design:
    - One master key (KEK) lives in `:hybridsocial, :message_encryption_key`.
    - Per-conversation keys are derived deterministically via HKDF-SHA256
      using the conversation id as the HKDF `info`. No DEK stored in DB.
    - Messages are encrypted with AES-256-GCM; ciphertext and nonce are
      stored; the 16-byte GCM tag is appended to the ciphertext.
    - `encryption_version = 1` identifies rows produced by this module.
      Version 0 means plaintext (legacy / federated import). New code
      always writes version 1.

  Security properties:
    - Defends against: DB dumps, backup theft, any adversary who gets
      the DB without the running server.
    - Does NOT defend against: a compromised running server, a malicious
      operator, a valid court order. The server has the master key.

  This is labeled "encrypted at rest" in the UI — never "end-to-end."
  """

  @version 1
  @key_size 32
  @nonce_size 12

  @doc "The current encryption version written by this module."
  def current_version, do: @version

  @doc """
  Encrypt `plaintext` for the given conversation. Returns
  `{:ok, ciphertext, nonce, version}` or `{:error, reason}`.

  The ciphertext includes the 16-byte GCM authentication tag.
  """
  def encrypt(plaintext, conversation_id)
      when is_binary(plaintext) and is_binary(conversation_id) do
    with {:ok, key} <- conversation_key(conversation_id) do
      nonce = :crypto.strong_rand_bytes(@nonce_size)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          nonce,
          plaintext,
          aad(conversation_id),
          true
        )

      {:ok, ciphertext <> tag, nonce, @version}
    end
  end

  @doc """
  Decrypt `ciphertext` for the given conversation.
  Returns `{:ok, plaintext}` or `{:error, reason}`.
  """
  def decrypt(ciphertext, nonce, conversation_id, version)
      when is_binary(ciphertext) and is_binary(nonce) and is_binary(conversation_id) and
             is_integer(version) do
    cond do
      version != @version ->
        {:error, {:unsupported_version, version}}

      byte_size(ciphertext) < 16 ->
        {:error, :ciphertext_too_short}

      byte_size(nonce) != @nonce_size ->
        {:error, :invalid_nonce}

      true ->
        with {:ok, key} <- conversation_key(conversation_id) do
          tag_size = 16
          ct_size = byte_size(ciphertext) - tag_size
          <<ct::binary-size(ct_size), tag::binary-size(tag_size)>> = ciphertext

          case :crypto.crypto_one_time_aead(
                 :aes_256_gcm,
                 key,
                 nonce,
                 ct,
                 aad(conversation_id),
                 tag,
                 false
               ) do
            :error -> {:error, :decryption_failed}
            plaintext when is_binary(plaintext) -> {:ok, plaintext}
          end
        end
    end
  end

  # Binds the ciphertext to the conversation id as AEAD additional data.
  # A message encrypted for conversation A cannot be replayed into
  # conversation B — the AAD mismatch will fail the GCM tag check.
  defp aad(conversation_id), do: "hs:dm:conv:" <> conversation_id

  defp conversation_key(conversation_id) do
    with {:ok, master} <- master_key() do
      prk = :crypto.mac(:hmac, :sha256, <<>>, master)
      info = "hs:dm:conv-key:v#{@version}:" <> conversation_id
      key = :crypto.mac(:hmac, :sha256, prk, info <> <<1>>)
      {:ok, binary_part(key, 0, @key_size)}
    end
  end

  defp master_key do
    case Application.get_env(:hybridsocial, :message_encryption_key) do
      nil ->
        {:error, :missing_master_key}

      value when is_binary(value) ->
        decode_master(value)

      _ ->
        {:error, :invalid_master_key}
    end
  end

  defp decode_master(value) do
    case Base.decode64(value) do
      {:ok, <<key::binary-size(@key_size)>>} ->
        {:ok, key}

      {:ok, other} when byte_size(other) >= @key_size ->
        {:ok, binary_part(other, 0, @key_size)}

      _ ->
        # Accept raw UTF-8 string of sufficient length as a dev convenience.
        # Production must use a base64-encoded 32-byte random key.
        if byte_size(value) >= @key_size do
          {:ok, binary_part(value, 0, @key_size)}
        else
          {:error, :master_key_too_short}
        end
    end
  end
end
