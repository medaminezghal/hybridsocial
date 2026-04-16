defmodule Hybridsocial.Messaging.CryptoTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Hybridsocial.Messaging.Crypto

  @conv_id "11111111-1111-1111-1111-111111111111"
  @other_conv "22222222-2222-2222-2222-222222222222"

  describe "encrypt/decrypt round-trip" do
    test "recovers the plaintext" do
      assert {:ok, ct, nonce, version} = Crypto.encrypt("hello world", @conv_id)
      assert {:ok, "hello world"} = Crypto.decrypt(ct, nonce, @conv_id, version)
    end

    test "handles empty plaintext" do
      assert {:ok, ct, nonce, version} = Crypto.encrypt("", @conv_id)
      assert {:ok, ""} = Crypto.decrypt(ct, nonce, @conv_id, version)
    end

    test "handles unicode and binary content" do
      plaintext = "مرحبا — 🔒 — 안녕"
      assert {:ok, ct, nonce, version} = Crypto.encrypt(plaintext, @conv_id)
      assert {:ok, ^plaintext} = Crypto.decrypt(ct, nonce, @conv_id, version)
    end

    test "encryption is randomized (same plaintext → different ciphertext)" do
      {:ok, ct_a, nonce_a, _} = Crypto.encrypt("same text", @conv_id)
      {:ok, ct_b, nonce_b, _} = Crypto.encrypt("same text", @conv_id)

      refute ct_a == ct_b
      refute nonce_a == nonce_b
    end
  end

  describe "cross-conversation safety" do
    test "ciphertext from one conversation cannot be decrypted by another" do
      {:ok, ct, nonce, version} = Crypto.encrypt("secret for A", @conv_id)

      assert {:error, :decryption_failed} =
               Crypto.decrypt(ct, nonce, @other_conv, version)
    end

    test "tampered ciphertext fails authentication" do
      {:ok, ct, nonce, version} = Crypto.encrypt("authentic", @conv_id)

      mid = div(byte_size(ct), 2)
      <<head::binary-size(mid), byte, tail::binary>> = ct
      tampered = <<head::binary, bxor(byte, 1), tail::binary>>

      assert {:error, :decryption_failed} =
               Crypto.decrypt(tampered, nonce, @conv_id, version)
    end

    test "tampered nonce fails authentication" do
      {:ok, ct, nonce, version} = Crypto.encrypt("authentic", @conv_id)
      <<byte, rest::binary>> = nonce
      tampered_nonce = <<bxor(byte, 1), rest::binary>>

      assert {:error, :decryption_failed} =
               Crypto.decrypt(ct, tampered_nonce, @conv_id, version)
    end
  end

  describe "version checks" do
    test "rejects unknown version" do
      {:ok, ct, nonce, _} = Crypto.encrypt("any", @conv_id)

      assert {:error, {:unsupported_version, 99}} =
               Crypto.decrypt(ct, nonce, @conv_id, 99)
    end

    test "current_version/0 matches what encrypt/2 emits" do
      {:ok, _ct, _nonce, version} = Crypto.encrypt("any", @conv_id)
      assert version == Crypto.current_version()
    end
  end

  describe "input validation" do
    test "rejects wrong-sized nonce" do
      {:ok, ct, _nonce, version} = Crypto.encrypt("hi", @conv_id)

      assert {:error, :invalid_nonce} =
               Crypto.decrypt(ct, <<0, 0, 0>>, @conv_id, version)
    end

    test "rejects too-short ciphertext" do
      assert {:error, :ciphertext_too_short} =
               Crypto.decrypt(<<0>>, :crypto.strong_rand_bytes(12), @conv_id, 1)
    end
  end
end
