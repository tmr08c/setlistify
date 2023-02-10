defmodule Setlistify.Repo do
  use Ecto.Repo,
    otp_app: :setlistify,
    adapter: Ecto.Adapters.Postgres
end
