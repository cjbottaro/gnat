defmodule Gnat.Stream.Proto.MsgProto do
  @moduledoc """
  Struct that represents a message received as the result of a topic subscription.
  """
  use Gnat.Stream.Proto

  @typedoc """
  Represents a message received as the result of a topic subscription.
  """
  @type t :: %Gnat.Stream.Proto.MsgProto{
    subject: String.t,
    data: String.t,
    sequence: integer,
    timestamp: integer,
    reply: String.t,
    redelivered: boolean,
    crc32: String.t,
    nats_msg: Gnat.Proto.Msg.t
  }
end
