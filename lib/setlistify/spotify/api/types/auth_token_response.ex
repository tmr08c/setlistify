defmodule Spotify.API.Types.TokenResponse do
  @moduledoc """
  Represents the response from Spotify API when exchanging an authorization code for an access token.

  All fields are required and will be validated when creating the struct via `from_json!/1`.

  ## Fields

  * `access_token` - Token that can be provided in subsequent API calls
  * `expires_in` - Time period in seconds for which the access token is valid (typically 3600)
  * `refresh_token` - Token that can be used to obtain a new access token when the current one expires

  ## See Also

  - https://developer.spotify.com/documentation/web-api/tutorials/code-flow
  """

  @type t :: %__MODULE__{
          access_token: String.t(),
          expires_in: integer(),
          refresh_token: String.t()
        }

  @enforce_keys [:access_token, :expires_in, :refresh_token]
  defstruct @enforce_keys

  @doc """
  Creates a new TokenResponse struct from the JSON response.

  This function will raise a KeyError if any required field is missing from the JSON.

  ## Examples

  Notice the response includes `token_type` and `scope` fields, but these are
  ignored in our struct.

      iex> json_response = %{
      ...>   "access_token" => "NgCXRK...MzYjw",
      ...>   "token_type" => "Bearer",
      ...>   "scope" => "user-read-private user-read-email",
      ...>   "expires_in" => 3600,
      ...>   "refresh_token" => "NgAagA...Um_SHo"
      ...> }
      iex> Spotify.Auth.TokenResponse.from_json!(json_response)
      %Spotify.Auth.TokenResponse{
        access_token: "NgCXRK...MzYjw",
        expires_in: 3600,
        refresh_token: "NgAagA...Um_SHo"
      }

      iex> Spotify.Auth.TokenResponse.from_json!(%{"access_token" => "token"})
      ** (KeyError) key "token_type" not found in: %{"access_token" => "token"}
  """
  @spec from_json!(map()) :: t()
  def from_json!(json) do
    %__MODULE__{
      access_token: Map.fetch!(json, "access_token"),
      expires_in: Map.fetch!(json, "expires_in"),
      refresh_token: Map.fetch!(json, "refresh_token")
    }
  end
end
