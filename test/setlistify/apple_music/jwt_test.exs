defmodule Setlistify.AppleMusic.JWTTest do
  use ExUnit.Case, async: true

  alias Setlistify.AppleMusic.JWT

  # Test P-256 key pair generated with:
  #   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256
  #   openssl pkey -in private.pem -pubout
  @test_private_pem """
  -----BEGIN PRIVATE KEY-----
  MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPPtyY/6NgUDDyUOn
  X2sk64l0Mi4VQjc7pP/MpCvgLv+hRANCAAQN5Qh4TCaEdgmH2zjTZaIR8Pten3mw
  152R0P9vLEzTqu7g8GEK0G9Jlj9EhXl6xUxI/RlStMOsrNVBqRefSxZC
  -----END PRIVATE KEY-----
  """

  @test_public_pem """
  -----BEGIN PUBLIC KEY-----
  MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEDeUIeEwmhHYJh9s402WiEfD7Xp95
  sNedkdD/byxM06ru4PBhCtBvSZY/RIV5esVMSP0ZUrTDrKzVQakXn0sWQg==
  -----END PUBLIC KEY-----
  """

  @kid "TEST_KEY_ID"
  @iss "TEST_TEAM_ID"

  describe "sign/4" do
    test "returns a three-part JWT string" do
      token = JWT.sign(%{"iat" => 1_000, "exp" => 2_000}, @test_private_pem, @kid, @iss)

      assert [_, _, _] = String.split(token, ".")
    end

    test "header contains alg ES256 and the given kid" do
      token = JWT.sign(%{"iat" => 1_000, "exp" => 2_000}, @test_private_pem, @kid, @iss)

      [header_b64 | _] = String.split(token, ".")
      header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert header["alg"] == "ES256"
      assert header["kid"] == @kid
    end

    test "payload matches the provided claims" do
      claims = %{"iat" => 1_000, "exp" => 2_000, "foo" => "bar"}
      token = JWT.sign(claims, @test_private_pem, @kid, @iss)

      [_, payload_b64 | _] = String.split(token, ".")
      decoded = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert decoded["iss"] == @iss
      assert decoded["iat"] == 1_000
      assert decoded["exp"] == 2_000
      assert decoded["foo"] == "bar"
    end

    test "signature is exactly 64 bytes (raw R||S for P-256)" do
      token = JWT.sign(%{"iat" => 1_000, "exp" => 2_000}, @test_private_pem, @kid, @iss)

      [_, _, sig_b64] = String.split(token, ".")
      assert byte_size(Base.url_decode64!(sig_b64, padding: false)) == 64
    end

    test "signature verifies against the corresponding public key" do
      claims = %{"iat" => 1_000, "exp" => 2_000}
      token = JWT.sign(claims, @test_private_pem, @kid, @iss)

      [header_b64, payload_b64, sig_b64] = String.split(token, ".")
      signing_input = header_b64 <> "." <> payload_b64

      der_sig = sig_b64 |> Base.url_decode64!(padding: false) |> jws_sig_to_der()
      public_key = decode_public_key(@test_public_pem)

      other_public_pem = """
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEbqTLBm40IxQo3FAYIIg2jdQMJSg7
      mZdd/xiSC4aoS19U5sOFmTLUj3a1BPMSEkcXurWaLzzVK1MQBAxJZ8r2BQ==
      -----END PUBLIC KEY-----
      """

      assert :public_key.verify(signing_input, :sha256, der_sig, public_key)

      refute :public_key.verify(
               signing_input,
               :sha256,
               der_sig,
               decode_public_key(other_public_pem)
             )
    end

    test "different claims produce different tokens" do
      token1 = JWT.sign(%{"iat" => 1_000, "exp" => 2_000}, @test_private_pem, @kid, @iss)
      token2 = JWT.sign(%{"iat" => 2_000, "exp" => 3_000}, @test_private_pem, @kid, @iss)

      refute token1 == token2
    end
  end

  # Convert raw R||S (64 bytes) back to DER-encoded signature for Erlang's verify/4
  defp jws_sig_to_der(<<r::binary-size(32), s::binary-size(32)>>) do
    :public_key.der_encode(
      :"ECDSA-Sig-Value",
      {:"ECDSA-Sig-Value", :binary.decode_unsigned(r), :binary.decode_unsigned(s)}
    )
  end

  defp decode_public_key(pem) do
    [{_, _, _} = entry] = :public_key.pem_decode(pem)
    :public_key.pem_entry_decode(entry)
  end
end
