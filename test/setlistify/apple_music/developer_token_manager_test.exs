defmodule Setlistify.AppleMusic.DeveloperTokenManagerTest do
  use ExUnit.Case, async: false

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
end
