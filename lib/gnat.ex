require Logger

defmodule Gnat do
  use Connection

  alias Gnat.Proto

  @defaults [
    host: "localhost",
    port: 4222,
    cluster_id: "test-cluster",
    client_id: "gnat"
  ]
  def start_link(options \\ []) do
    options = Keyword.merge(@defaults, options) |> Enum.into(%{})
    Connection.start_link(Gnat.Connection, Enum.into(options, %{}))
  end

  def new_sid, do: SecureRandom.hex(4)

  def sub(pid, subject, sid, options \\ []) do
    raw_message = Proto.sub(subject, sid, options)
    GenServer.call(pid, {:transmit, raw_message})
  end

  def unsub(pid, sid, options \\ []) do
    raw_message = Proto.unsub(sid, options)
    GenServer.call(pid, {:transmit, raw_message})
  end

  def pub(pid, subject, payload, options \\ []) do
    raw_message = Proto.pub(subject, payload, options)
    GenServer.call(pid, {:transmit, raw_message})
  end

  def deliver_to(pid, dst) do
    GenServer.call(pid, {:deliver_to, dst})
  end

  def req_res(pid, subject, payload) do
    sid = new_sid
    temp_inbox = "req_res.#{sid}"

    # Let our connection know that messages from sid are part of a
    # request/response. We have to do this *before* subscribing otherwise
    # we introduce a subtle race condition.
    :ok = GenServer.call(pid, {:request, sid})

    :ok = sub(pid, temp_inbox, sid)
    :ok = unsub(pid, sid, max_msgs: 1) # This is what makes it temporary.
    :ok = pub(pid, subject, payload, reply_to: temp_inbox)

    # Block until we get a response.
    GenServer.call(pid, {:response, sid})
  end

  def next_msg(pid) do
    GenServer.call(pid, :next_msg)
  end

end
