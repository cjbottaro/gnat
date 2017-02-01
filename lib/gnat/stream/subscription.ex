defmodule Gnat.Stream.Subscription do
  @moduledoc false

  defstruct [:topic, :inbox, :inbox_sid, :ack_inbox]

  alias Gnat.Stream.Protobuf.{StartPosition}

  import Gnat, only: [new_sid: 0]

  def new(attributes \\ []) do
    attributes = Keyword.put_new(attributes, :inbox_sid, new_sid())
    attributes = Keyword.put_new(attributes, :inbox, "MsgProto.#{attributes[:inbox_sid]}")
    struct!(__MODULE__, attributes)
  end

  def start_position(atom) do
    atom |> Atom.to_string |> Macro.camelize |> String.to_atom |> StartPosition.value
  end

end
