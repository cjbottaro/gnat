require Logger

defmodule Gnat.Proto do

  def parse(message) do
    op = String.split(message, " ")
      |> Enum.at(0)
      |> String.downcase
      |> String.capitalize
    module = String.to_existing_atom("Elixir.Gnat.Proto.#{op}")
    apply(module, :parse, [message])
  end

  def connect(options) do
    json = options |> Enum.into(%{}) |> Poison.encode!
    "CONNECT #{json}"
  end

  def ping, do: "PING"

  def pong, do: "PONG"

  def pub(subject, payload, options \\ []) do
    reply_to = options[:reply_to]
    bytes = byte_size(payload)
    "PUB #{subject} #{reply_to} #{bytes}\r\n#{payload}"
  end

  def sub(options \\ []) do
    sid = options[:sid] || Gnat.new_sid
    subject = cond do
      s = options[:subject] -> s
      p = options[:prefix] -> "#{p}.#{sid}"
      true -> raise ArgumentError, "subject or prefix required"
    end
    queue_group = options[:queue_group]
    {subject, sid, "SUB #{subject} #{queue_group} #{sid}"}
  end

  def unsub(sid, options \\ []) do
    max_msgs = options[:max_msgs]
    "UNSUB #{sid} #{max_msgs}"
  end

end
