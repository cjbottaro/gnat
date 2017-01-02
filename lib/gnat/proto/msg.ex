defmodule Gnat.Proto.Msg do
  defstruct [:subject, :sid, :reply_to, :bytes, :payload]

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
