defmodule Gnat.Proto.Msg do
  @moduledoc """
  A struct representing a message received as a result of a subject subscription.
  """

  @typedoc """
  Represents a message received as a result of a subject subscription.

  * `:subject` - Subject this message was published to.
  * `:sid` - Sid of the subscription that received this message.
  * `:reply_to` - Subject the sender of this message wants a reply to.
  * `:bytes` - Number of bytes of the payload.
  * `:payload` - The payload of the message.
  """
  @type t :: %Gnat.Proto.Msg{subject: String.t, sid: String.t, reply_to: String.t, bytes: integer, payload: String.t}

  defstruct [:subject, :sid, :reply_to, :bytes, :payload]

  @doc false
  def parse(raw_message) do
    [header, payload | []] = String.split(raw_message, "\r\n", parts: 2)
    case String.split(header, " ") do
      [_op, subject, sid, reply_to, bytes | []] ->
        %__MODULE__{subject: subject, sid: sid, reply_to: reply_to, bytes: bytes, payload: payload}
      [_op, subject, sid, bytes | []] ->
        %__MODULE__{subject: subject, sid: sid, bytes: bytes, payload: payload}
    end
  end
end
