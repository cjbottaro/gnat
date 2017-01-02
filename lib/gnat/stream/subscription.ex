defmodule Gnat.Stream.Subscription do
  defstruct [:topic, :inbox, :inbox_sid, :response_inbox, :ack_outbox, :blocker]

  alias Gnat.Stream.Protobuf.{StartPosition}

  import Gnat, only: [new_sid: 0]

  def new(attributes \\ []) do
    attributes = Keyword.put_new(attributes, :inbox_sid, new_sid)
    attributes = attributes
      |> Keyword.put_new(:inbox, "MsgProto.#{attributes[:inbox_sid]}")
      |> Keyword.put_new(:response_inbox, "SubscriptionResponse.#{new_sid}")
    struct!(__MODULE__, attributes)
  end

  def start_position(atom) do
    atom |> Atom.to_string |> Macro.camelize |> String.to_atom |> StartPosition.value
  end

end
