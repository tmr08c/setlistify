defmodule Setlistify.AppleMusic.DeveloperTokenManagerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Setlistify.AppleMusic.DeveloperTokenManager

  @test_private_pem """
  -----BEGIN PRIVATE KEY-----
  MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPPtyY/6NgUDDyUOn
  X2sk64l0Mi4VQjc7pP/MpCvgLv+hRANCAAQN5Qh4TCaEdgmH2zjTZaIR8Pten3mw
  152R0P9vLEzTqu7g8GEK0G9Jlj9EhXl6xUxI/RlStMOsrNVBqRefSxZC
  -----END PRIVATE KEY-----
  """

  setup do
    Application.put_env(:setlistify, :apple_music_team_id, "TEST_TEAM_ID")
    Application.put_env(:setlistify, :apple_music_key_id, "TEST_KEY_ID")
    Application.put_env(:setlistify, :apple_music_private_key, @test_private_pem)

    on_exit(fn ->
      Application.delete_env(:setlistify, :apple_music_team_id)
      Application.delete_env(:setlistify, :apple_music_key_id)
      Application.delete_env(:setlistify, :apple_music_private_key)
    end)

    :ok
  end

  describe "with a valid private key" do
    setup do
      start_supervised!(DeveloperTokenManager)
      :ok
    end

    test "get_token/0 returns the same cached token on repeated calls" do
      assert DeveloperTokenManager.get_token() == DeveloperTokenManager.get_token()
    end

    test "token is refreshed when :refresh_token message is sent" do
      token_before = DeveloperTokenManager.get_token()

      pid = Process.whereis(DeveloperTokenManager)
      send(pid, :refresh_token)
      :sys.get_state(pid)

      refute DeveloperTokenManager.get_token() == token_before
    end

    test "get_token/0 returns nil when the cached token has expired" do
      token_before = DeveloperTokenManager.get_token()
      assert is_binary(token_before)

      # Push expires_at into the past without going through the normal refresh
      # path, so we can verify the expiry guard in handle_call(:get_token, ...).
      :sys.replace_state(DeveloperTokenManager, fn state ->
        %{state | expires_at: System.system_time(:second) - 60}
      end)

      assert DeveloperTokenManager.get_token() == nil
    end
  end

  describe "when the private key is invalid" do
    setup do
      Application.put_env(:setlistify, :apple_music_private_key, "not-a-pem")
      :ok
    end

    test "stays alive with get_token/0 returning nil instead of crashing" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_interval_ms: 60_000})
        :sys.get_state(DeveloperTokenManager)
      end)

      pid = Process.whereis(DeveloperTokenManager)
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert DeveloperTokenManager.get_token() == nil
    end

    test "logs a stacktraced error identifying the failure step" do
      log =
        capture_log(fn ->
          start_supervised!({DeveloperTokenManager, retry_interval_ms: 60_000})
          :sys.get_state(DeveloperTokenManager)
        end)

      assert log =~ "DeveloperTokenManager failed to generate token"
      assert log =~ ~r/\*\* \([A-Z][A-Za-z]+Error\)/
      assert log =~ "lib/setlistify/apple_music/"
    end

    test "logs a human-readable 'Apple Music sign-in is DISABLED' banner" do
      log =
        capture_log(fn ->
          start_supervised!({DeveloperTokenManager, retry_interval_ms: 60_000})
          :sys.get_state(DeveloperTokenManager)
        end)

      assert log =~ "Apple Music sign-in is DISABLED"
      assert log =~ "APPLE_MUSIC_PRIVATE_KEY"
    end

    test "retries on the configured interval and re-logs the banner on continued failure" do
      log =
        capture_log(fn ->
          start_supervised!({DeveloperTokenManager, retry_interval_ms: 10})
          Process.sleep(100)
          :sys.get_state(DeveloperTokenManager)
        end)

      banner_count =
        log
        |> String.split("Apple Music sign-in is DISABLED")
        |> length()
        |> Kernel.-(1)

      assert banner_count >= 2,
             "expected banner to appear at least twice, saw #{banner_count}\n\nLog:\n#{log}"
    end

    test "recovers via regenerate_token/0 once the configured PEM is valid" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_interval_ms: 60_000})
        :sys.get_state(DeveloperTokenManager)
      end)

      assert DeveloperTokenManager.get_token() == nil

      Application.put_env(:setlistify, :apple_music_private_key, @test_private_pem)

      token = DeveloperTokenManager.regenerate_token()
      assert is_binary(token)
      assert DeveloperTokenManager.get_token() == token
    end

    test "recovers via the periodic retry once the configured PEM is valid" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_interval_ms: 10})
        :sys.get_state(DeveloperTokenManager)
      end)

      assert DeveloperTokenManager.get_token() == nil

      Application.put_env(:setlistify, :apple_music_private_key, @test_private_pem)
      Process.sleep(100)
      :sys.get_state(DeveloperTokenManager)

      token = DeveloperTokenManager.get_token()
      assert is_binary(token)
    end
  end
end
