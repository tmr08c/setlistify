defmodule Setlistify.AppleMusic.UserSession do
  @type t :: %__MODULE__{
          user_token: String.t(),
          user_id: String.t(),
          storefront: String.t()
        }

  @enforce_keys [:user_token, :user_id, :storefront]
  defstruct [:user_token, :user_id, :storefront]
end
