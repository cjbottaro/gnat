defmodule Gnat.Stream do
  @moduledoc """
  Use this module to connect to and interact with a NATS Streaming server.

  The term "topic" is used to differentiate from a NATS subject. A topic in
  the context of this module is the stream subject or channel (like a Kafka
  topic).

  ### Examples

  Delivering messages to a pid...

      {:ok, conn} = Gnat.Stream.start_link(deliver_to: self)
      Gnat.Stream.subscribe(conn, "foo")
      receive do
        {:nats_stream_msg, msg} -> Gnat.Stream.ack(conn, msg)
      end

  Collecting messages in an internal buffer...

      {:ok, conn} = Gnat.Stream.start_link(deliver_to: self)
      Gnat.Stream.subscribe(conn, "foo")
      msg = Gnat.Stream.next_msg(conn)
      Gnat.Stream.ack(conn, msg)
  """

  @typedoc """
  Represents a connection to a NATS Streaming server.
  """
  @type conn :: pid

  @doc """
  Connect to a NATS Streaming server.

  ## Options

    * `:host` - Host to connect to. Default: `"localhost"`
    * `:port` - Port to connect to. Default: `4222`
    * `:cluster_id` - Name of the NATS Streaming server to connect to. Used
    for handshake protocol. Default: `"test-cluster"`
    * `:discover_prefix` - Prefix of subject for handshake protocol. Default:
    `"_STAN.discover"`
    * `:deliver_to` - Pid to deliver messages to. Default: `nil`

  If `:deliver_to` is a `pid`, then messages will be sent to that process in
  the form of `{:nats_stream_msg, msg}` where `msg` is of the type
  `t:Gnat.Stream.Proto.MsgProto.t/0`.

  If `:deliver_to` is nil, then messages will be collected in an internal buffer
  to be fetched with `next_msg/1`.
  """
  @defaults [
    host: "localhost",
    port: 4222,
    cluster_id: "test-cluster",
    client_id: "gnat",
    discover_prefix: "_STAN.discover",
    deliver_to: nil
  ]
  @spec start_link(Keyword.t) :: {:ok, conn} | {:error, String.t}
  def start_link(options \\ []) do
    options = Keyword.merge(@defaults, options)
    Gnat.Stream.Connection.start_link(options)
  end

  @doc """
  Subscribe to a topic.

  ## Options

    * `:max_in_flight` - Max in flight messages. Default: `1`
    * `:ack_wait_in_secs` - How many seconds to wait for an ack before redelivering. Default: `30`
    * `:start_position` - Where in the topic to start receiving messages from. Default: `:new_only`
    * `:start_sequence` - Start sequence number. Default: `nil`
    * `:start_time_delta` - Start time. Default: `nil`

  ## Options for `:start_position`

    * `:new_only` - Send only new messages.
    * `:last_received` - Send only the last received message.
    * `:time_delta_start` - Send messages from duration specified in the `:start_time_delta` field.
    * `:sequence_start` - Send messages starting from the sequence in the `:start_sequence` field.
    * `:first` - Send all available messages.

  """
  @defaults [
    max_in_flight: 1,
    ack_wait_in_secs: 30,
    start_position: :new_only
  ]
  @spec subscribe(conn, String.t, Keyword.t) :: :ok
  def subscribe(conn, topic, options \\ []) do
    options = Keyword.merge(@defaults, options)
    GenServer.call(conn, {:subscribe, topic, options})
  end

  @doc """
  Receive and remove a message from the internal buffer.

  If `start_link/1` was called without `:deliver_to` set, then any received
  message will be stored in an internal buffer. Use this method to pop a message
  off that buffer.

  Returns `nil` if there are no messages on the buffer.

  ## Example

      {:ok, conn} = Gnat.Stream.start_link
      Gnat.Stream.subscribe(conn, "foo")
      msg = Gnat.Stream.next_msg(conn)

  """
  @spec next_msg(conn) :: Gnat.Stream.Proto.MsgProto.t | nil
  def next_msg(conn) do
    GenServer.call(conn, :next_msg)
  end

  @doc """
  Acknowledge a message.

  Messages must be acknowledged so the server knows when to send the next
  message and also not to redeliver messages.

  ## Example

      receive do
        {:nats_stream_msg, msg} -> Gnat.Stream.ack(conn, msg)
      end

  """
  @spec ack(conn, Gnat.Stream.Proto.MsgProto.t) :: :ok
  def ack(conn, msg) do
    GenServer.call(conn, {:ack, msg})
  end

  @doc """
  Publish a message to a topic.

  ## Options

    * `:ack` - Block until the server acknowledges the publish. Default: `true`

  ## Example

      # Receive an ack from server before returning.
      Gnat.Stream.publish(conn, "foo", "hello")

      # Publish without waiting for an ack.
      Gnat.Stream.publish(conn, "foo", "bye", ack: false)

  """
  @defaults [
    ack: true
  ]
  @spec publish(conn, String.t, String.t, Keyword.t) :: :ok
  def publish(conn, topic, data, options \\ []) do
    options = Keyword.merge(@defaults, options)
    GenServer.call(conn, {:publish, topic, data, options})
  end

end
