require Logger

defmodule Gnat do
  @moduledoc """
  Use this module to connect to and interact with a NATS server.

  Messages can either be collected into an internal buffer or delivered directly
  to an Elixir process, depending on how you call `start_link/1`.

  Using the internal buffer...
      {:ok, conn} = Gnat.start_link
      Gnat.sub(conn, "foo", "sid123")
      msg = Gnat.next_msg(conn)
      IO.puts "\#{msg.subject}: \#{msg.payload}"

  Directly delivering to a process...
      {:ok, conn} = Gnat.start_link(deliver_to: self)
      Gnat.sub(conn, "foo", "sid123")
      receive do
        {:nats_msg, msg} -> IO.puts "\#{msg.subject}: \#{msg.payload}"
      end
  """

  use Connection

  alias Gnat.Proto

  @typedoc """
  Represents a connection to a NATS server.
  """
  @type conn :: pid

  @doc """
  Create a new connection to a NATS server.

  ## Options

    * `:host` - Host to connect to. Default `"localhost"`
    * `:port` - Port to connect to. Default `4222`
    * `:cluster_id` - Name of cluster. Default `"test-cluster"`
    * `:client_id` - Each connection should have a unique id. Default `"gnat"`
    * `:deliver_to` - Pid where messages (MSG) should be delivered. Default `nil`

  If `:deliver_to` is nil, then messages will be collected in an internal buffer
  that can be fetched from using `Gnat.next_msg/1`.

  If `:deliver_to` is a `pid` then messages will sent there with the form `{:nats_msg, msg}`
  where `msg` is a `t:Gnat.Proto.Msg.t/0`.

  ## Examples

      {:ok, conn} = Gnat.start_link(deliver_to: self)
      Gnat.sub(conn, "foo", "123abc")

  """
  @spec start_link(Keyword.t) :: {:ok, conn} | {:error, atom}
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

  @doc """
  Generate a unique sid.

  The sid is a hex string representing random `bytes` bytes.
  """
  @spec new_sid(integer) :: String.t
  def new_sid(bytes \\ 4), do: SecureRandom.hex(bytes)

  @doc """

  Subscribe to a subject.

  ## Options

    * `:queue_group` - Name of queue group for this subscriber to join. Default: `nil`

  """
  @spec sub(conn, String.t, String.t, Keyword.t) :: :ok
  def sub(conn, subject, sid, options \\ []) do
    raw_message = Proto.sub(subject, sid, options)
    GenServer.call(conn, {:transmit, raw_message})
  end

  @doc """

  Unsubscribe from a subject.

  ## Options

    * `:max_msgs` - Number of message to receive before auto-unsubscribing. Default: `nil`

  """
  @spec unsub(conn, String.t, Keyword.t) :: :ok
  def unsub(conn, sid, options \\ []) do
    raw_message = Proto.unsub(sid, options)
    GenServer.call(conn, {:transmit, raw_message})
  end

  @doc """
  Publish a message to a subject.

  ## Options

    * `:reply_to` - Subject that the receiver of this message should reply to. Default: `nil`

  """
  @spec pub(conn, String.t, String.t, Keyword.t) :: :ok
  def pub(conn, subject, payload, options \\ []) do
    raw_message = Proto.pub(subject, payload, options)
    GenServer.call(conn, {:transmit, raw_message})
  end

  @doc """
  Synchronous request/response.

  As described [here](https://nats.io/documentation/concepts/nats-req-rep/).

  As of now, only point-to-point is supported, but one-to-many is on the roadmap.

  Return value is `{:ok, msg}` where `msg` is `t:Gnat.Proto.Msg.t/0`.

  ## Examples

      # In one process...
      {:ok, conn} = Gnat.start_link(client_id: "server", deliver_to: self)
      Gnat.sub(conn, "ping_server", "sid123")
      receive do
        {:nats_msg, msg} -> Gnat.pub(conn, msg.reply_to, msg.payload)
      end

      # In another process...
      {:ok, conn} = Gnat.start_link(client_id: "client")
      {:ok, msg} = Gnat.req_res(conn, "ping_server", "hello world!")
      IO.puts msg.payload
      "hello world!"
      :ok

  """
  @spec req_res(conn, String.t, String.t) :: {:ok, Gnat.Proto.Msg.t}
  def req_res(conn, subject, payload) do
    sid = new_sid
    temp_inbox = "req_res.#{sid}"

    # Let our connection know that messages from sid are part of a
    # request/response. We have to do this *before* subscribing otherwise
    # we introduce a subtle race condition.
    :ok = GenServer.call(conn, {:request, sid})

    :ok = sub(conn, temp_inbox, sid)
    :ok = unsub(conn, sid, max_msgs: 1) # This is what makes it temporary.
    :ok = pub(conn, subject, payload, reply_to: temp_inbox)

    # Block until we get a response.
    GenServer.call(conn, {:response, sid})
  end

  @doc """
  Fetches a NATS message.

  When `:deliver_to` is not set in the call to `start_link/1`, then messages
  will be collected in an internal buffer. Calling `next_msg/1` will pop a
  single message off that buffer and return it.

  It will return nil if there are no messages on the buffer.
  """
  @spec next_msg(conn) :: Gnat.Proto.Msg.t | nil
  def next_msg(conn), do: GenServer.call(conn, :next_msg)

end
