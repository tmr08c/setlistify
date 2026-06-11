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
        start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
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
          start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
          :sys.get_state(DeveloperTokenManager)
        end)

      assert log =~ "DeveloperTokenManager failed to generate token"
      assert log =~ ~r/\*\* \([A-Z][A-Za-z]+Error\)/
      assert log =~ "lib/setlistify/apple_music/"
    end

    test "logs a human-readable 'Apple Music sign-in is DISABLED' banner" do
      log =
        capture_log(fn ->
          start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
          :sys.get_state(DeveloperTokenManager)
        end)

      assert log =~ "Apple Music sign-in is DISABLED"
      assert log =~ "APPLE_MUSIC_PRIVATE_KEY"
    end

    test "retries on the configured interval and re-logs the banner on continued failure" do
      log =
        capture_log(fn ->
          start_supervised!({DeveloperTokenManager, retry_base_ms: 10, retry_max_ms: 50, retry_multiplier: 2})

          Process.sleep(150)
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
        start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
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
        start_supervised!({DeveloperTokenManager, retry_base_ms: 10})
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

  describe "retry backoff schedule" do
    setup do
      Application.put_env(:setlistify, :apple_music_private_key, "not-a-pem")
      :ok
    end

    test "current_retry_ms grows by the multiplier on each failure, capped at max_ms" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_base_ms: 10_000, retry_max_ms: 40_000, retry_multiplier: 2})

        :sys.get_state(DeveloperTokenManager)
      end)

      # First failure happened during init/continue. The *next* retry interval
      # was advanced to base * multiplier = 20_000.
      assert state().current_retry_ms == 20_000

      drive_retry()
      assert state().current_retry_ms == 40_000

      drive_retry()
      # Capped at max_ms instead of doubling to 80_000.
      assert state().current_retry_ms == 40_000

      drive_retry()
      assert state().current_retry_ms == 40_000
    end

    test "current_retry_ms resets to retry_base_ms after a successful recovery" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_base_ms: 5_000, retry_max_ms: 60_000, retry_multiplier: 4})

        :sys.get_state(DeveloperTokenManager)
      end)

      drive_retry()
      drive_retry()
      assert state().current_retry_ms > 5_000

      Application.put_env(:setlistify, :apple_music_private_key, @test_private_pem)
      drive_retry()

      assert state().current_retry_ms == 5_000
    end

    test "regenerate_token/0 resets the backoff even when regeneration fails" do
      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_base_ms: 5_000, retry_max_ms: 60_000, retry_multiplier: 4})

        :sys.get_state(DeveloperTokenManager)
      end)

      drive_retry()
      drive_retry()
      grown = state().current_retry_ms
      assert grown > 5_000

      capture_log(fn -> DeveloperTokenManager.regenerate_token() end)

      # Reset to the base interval so the next scheduled retry starts fresh.
      assert state().current_retry_ms == 5_000
    end

    defp drive_retry do
      capture_log(fn ->
        send(Process.whereis(DeveloperTokenManager), :retry_generate)
        :sys.get_state(DeveloperTokenManager)
      end)
    end

    defp state, do: :sys.get_state(DeveloperTokenManager)
  end

  describe "telemetry" do
    setup do
      handler_id = {__MODULE__, self()}
      test_pid = self()

      :telemetry.attach(
        handler_id,
        DeveloperTokenManager.telemetry_event(),
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits :ok event with phase: :generate on a healthy startup" do
      start_supervised!(DeveloperTokenManager)

      assert_receive {:telemetry, [:setlistify, :apple_music, :developer_token, :attempt], %{count: 1, healthy: 1},
                      %{phase: :generate, outcome: :ok}}
    end

    test "emits :error event with phase: :generate when the PEM is invalid" do
      Application.put_env(:setlistify, :apple_music_private_key, "not-a-pem")

      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
        :sys.get_state(DeveloperTokenManager)
      end)

      assert_receive {:telemetry, [:setlistify, :apple_music, :developer_token, :attempt], %{count: 1, healthy: 0},
                      %{phase: :generate, outcome: :error}}
    end

    test "emits phase: :regenerate when regenerate_token/0 is called" do
      start_supervised!(DeveloperTokenManager)
      # Drain the startup :generate event so the :regenerate assertion can't pick it up.
      assert_receive {:telemetry, _, _, %{phase: :generate}}

      DeveloperTokenManager.regenerate_token()

      assert_receive {:telemetry, _, %{healthy: 1}, %{phase: :regenerate, outcome: :ok}}
    end

    test "emits phase: :refresh when the scheduled refresh fires" do
      start_supervised!(DeveloperTokenManager)
      assert_receive {:telemetry, _, _, %{phase: :generate}}

      send(Process.whereis(DeveloperTokenManager), :refresh_token)
      :sys.get_state(DeveloperTokenManager)

      assert_receive {:telemetry, _, %{healthy: 1}, %{phase: :refresh, outcome: :ok}}
    end

    test "emits phase: :retry when the retry timer fires" do
      Application.put_env(:setlistify, :apple_music_private_key, "not-a-pem")

      capture_log(fn ->
        start_supervised!({DeveloperTokenManager, retry_base_ms: 60_000})
        :sys.get_state(DeveloperTokenManager)
      end)

      assert_receive {:telemetry, _, _, %{phase: :generate, outcome: :error}}

      capture_log(fn ->
        send(Process.whereis(DeveloperTokenManager), :retry_generate)
        :sys.get_state(DeveloperTokenManager)
      end)

      assert_receive {:telemetry, _, %{healthy: 0}, %{phase: :retry, outcome: :error}}
    end
  end
end
