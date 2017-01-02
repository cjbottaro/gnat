require Logger

defmodule Gnat do
  use Connection

  alias Gnat.{Proto, Buffer}
  alias Proto.{Info, Ping, Pong, Msg}

  def new_sid, do: SecureRandom.hex(4)

  @defaults [
    host: "localhost",
    port: 4222,
    cluster_id: "test-cluster",
    client_id: "gnat"
  ]
  def start_link(options \\ []) do
    options = Keyword.merge(@defaults, options) |> Enum.into(%{})
    Connection.start_link(__MODULE__, Enum.into(options, %{}))
  end

  def sub(pid, options \\ []) do
    {subject, sid, raw_message} = Proto.sub(options)
    {GenServer.call(pid, {:transmit, raw_message}), subject, sid}
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

  def req_res(pid, options \\ []) do
    sid = Keyword.get(options, :sid, new_sid)
    recv_at = cond do
      s = options[:recv_at] -> s
      p = options[:recv_at_prefix] -> "#{p}.#{sid}"
      true -> raise ArgumentError, "recv_at or recv_at_prefix required"
    end
    send_to = Keyword.fetch!(options, :send_to)
    payload = Keyword.fetch!(options, :payload)

    {:ok, _, _ } = sub(pid, subject: recv_at, sid: sid)
    :ok = unsub(pid, sid, max_msgs: 1)
    :ok = pub(pid, send_to, payload, reply_to: recv_at)

    {:ok, recv_at, sid}
  end

  def next_msg(pid) do
    GenServer.call(pid, :next_msg)
  end

  def init(options) do
    {:ok, socket} = :gen_tcp.connect(
      String.to_char_list(options.host),
      options.port,
      [:binary, active: :once]
    )

    Proto.connect(
      verbose: false,
      pedantic: false,
      lang: "Elixir",
      version: "1.0",
      protocol: 1
    ) |> transmit(socket)

    Proto.ping |> transmit(socket)

    state = %{
      socket: socket,
      buffer: "",
      deliver_to: nil,
      msgs: []
    } |> Map.merge(options)

    {:connect, nil, state}
  end

  def connect(_info, state) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    Logger.debug "Closing socket"
    :gen_tcp.close(state.socket)
  end

  def handle_info({:tcp, socket, data}, state) do
    %{ buffer: buffer } = state

    {messages, buffer} = Buffer.process(buffer <> data)

    Enum.each messages, fn message ->
      GenServer.cast(self, {:message, message})
    end

    state = %{state | buffer: buffer}

    # Allow the socket to send us the next message
    :inet.setopts(socket, active: :once)

    {:noreply, state}
  end

  def handle_cast({:message, raw_message}, state) do
    Logger.debug "<<- #{raw_message}"
    Proto.parse(raw_message) |> handle_message(state)
  end

  def handle_message(%Info{}, state) do
    {:noreply, state}
  end

  def handle_message(%Ping{}, state) do
    Proto.pong |> transmit(state.socket)
    {:noreply, state}
  end

  def handle_message(%Pong{}, state) do
    {:noreply, state}
  end

  def handle_message(%Msg{} = msg, state) do
    if state.deliver_to do
      send(state.deliver_to, {:nats_msg, msg})
      {:noreply, state}
    else
      {:noreply, %{state | msgs: [msg | state.msgs]}}
    end
  end

  def handle_call({:transmit, raw_message}, _from, state) do
    transmit(raw_message, state.socket)
    {:reply, :ok, state}
  end

  def handle_call({:deliver_to, dst}, _from, state) do
    Enum.each(state.msgs, fn msg -> send(dst, {:nats_msg, msg}) end)
    {:reply, :ok, %{state | deliver_to: dst, msgs: []}}
  end

  def handle_call(:next_msg, _from, state) do
    %{msgs: msgs} = state
    msg = List.last(msgs)
    msgs = List.delete_at(msgs, -1)
    {:reply, msg, %{state | msgs: msgs}}
  end

  defp transmit(raw_message, socket) do
    Logger.debug "->> #{raw_message}"
    :gen_tcp.send(socket, "#{raw_message}\r\n")
  end

end
