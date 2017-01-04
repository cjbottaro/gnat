defmodule Gnat.Stream.Proto.Heartbeat do
  @moduledoc false
  defstruct [:nats_msg]

  def new(nats_msg) do
    struct!(__MODULE__, nats_msg: nats_msg)
  end

end
