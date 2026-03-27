defmodule Setlistify.AppleMusic.JWT do
  @moduledoc """
  Generates ES256-signed JWTs for Apple Music API authentication.

  Handles PKCS#8 PEM keys — the format Apple distributes as `.p8` files
  (`-----BEGIN PRIVATE KEY-----`).
  """

  @doc """
  Creates an ES256-signed JWT from `claims`.

  `pem` must contain a PKCS#8-wrapped EC P-256 private key (Apple's `.p8` format).
  `kid` is embedded in the JWT header so Apple can identify the signing key.
  """
  @spec sign(claims :: map(), pem :: String.t(), kid :: String.t(), iss :: String.t()) :: String.t()
  def sign(
        claims,
        pem \\ Application.fetch_env!(:setlistify, :apple_music_private_key),
        kid \\ Application.fetch_env!(:setlistify, :apple_music_key_id),
        iss \\ Application.fetch_env!(:setlistify, :apple_music_team_id)
      ) do
    header_b64 =
      %{"alg" => "ES256", "kid" => kid} |> Jason.encode!() |> Base.url_encode64(padding: false)

    payload_b64 =
      Map.put_new(claims, "iss", iss) |> Jason.encode!() |> Base.url_encode64(padding: false)

    signing_input = header_b64 <> "." <> payload_b64

    private_key =
      with [{:PrivateKeyInfo, _, _} = entry] <- :public_key.pem_decode(pem),
           do: :public_key.pem_entry_decode(entry)

    sig_b64 =
      signing_input
      |> :public_key.sign(:sha256, private_key)
      |> der_to_jws_sig()
      |> Base.url_encode64(padding: false)

    signing_input <> "." <> sig_b64
  end

  # Convert Erlang's DER-encoded ECDSA signature to the raw R||S format
  # required by JWS (RFC 7518 §3.4). Each component is zero-padded to 32 bytes.
  defp der_to_jws_sig(der) do
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    encode_int(r) <> encode_int(s)
  end

  defp encode_int(n) do
    bin = :binary.encode_unsigned(n)
    pad_bits = (32 - byte_size(bin)) * 8
    <<0::size(pad_bits), bin::binary>>
  end
end
