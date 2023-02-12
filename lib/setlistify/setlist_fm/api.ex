defmodule Setlistify.SetlistFm.API do
  @callback search(String.t()) :: map()

  def search(query), do: impl().search(query)

  defp impl, do: Setlistify.SetlistFm.API.MockClient
end
