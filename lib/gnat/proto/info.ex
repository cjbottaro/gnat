defmodule Gnat.Proto.Info do
  @moduledoc false
  defstruct [
    :server_id, :version, :go, :host, :port, :auth_required,
    :ssl_required, :tls_required, :tls_verify, :max_payload
  ]

  def parse(message) do
    attributes = String.split(message, " ", parts: 2)
      |> Enum.at(1)
      |> Poison.decode!
      |> atomify_keys
    struct!(__MODULE__, attributes)
  end

  defp atomify_keys(map) do
    Enum.reduce map, %{}, fn({k, v}, map) ->
      Map.put(map, String.to_atom(k), v)
    end
  end
end
