require Logger

defmodule Gnat.Stream.Connection do
  @moduledoc false

  use Connection

  alias Gnat.Stream.Proto
  alias Proto.{Heartbeat, ConnectResponse, SubscriptionResponse, MsgProto, PubAck}
  alias Gnat.Stream.Subscription

  def start_link(options) do
    Connection.start_link(__MODULE__, options)
  end

  def init(options) do
    {:ok, conn} = Gnat.start_link(Keyword.put(options, :deliver_to, self))

    options = Enum.into(options, %{})
    %{
      client_id: client_id,
      cluster_id: cluster_id,
      discover_prefix: discover_prefix
    } = options

    # Setup and subscribe to heartbeat inbox.
    sid = Gnat.new_sid
    heart_inbox = "Heartbeat.#{sid}"
    :ok = Gnat.sub(conn, heart_inbox, sid)

    # Make the connection request syncronously.
    Logger.debug "->> ConnectRequest"
    connect_request = Proto.connect_request(clientID: client_id, heartbeatInbox: heart_inbox)
    {:ok, nats_msg} = Gnat.req_res(conn, "#{discover_prefix}.#{cluster_id}", connect_request)
    response = ConnectResponse.new(nats_msg)
    connect_attributes = %{
      close_requests: response.close_requests,
      pub_prefix: response.pub_prefix,
      sub_close_requests: response.sub_close_requests,
      sub_requests: response.sub_requests,
      unsub_requests: response.unsub_requests
    }
    Logger.debug "<<- ConnectResponse"

    if response.error do
      GenServer.stop(conn)
      {:error, response.error}
    else
      state = options
        |> Map.merge(connect_attributes)
        |> Map.merge(%{
          conn: conn,
          subscriptions: %{},
          msg_protos: []
        })

      {:connect, nil, state}
    end
  end

  def terminate(_, state) do
    %{
      conn: conn,
      client_id: client_id,
      close_requests: close_requests
    } = state
    close_request = Proto.close_request(client_id)
    {:ok, _} = Gnat.req_res(conn, close_requests, close_request)
    GenServer.stop(state.conn)
  end

  def connect(_info, state) do
    {:ok, state}
  end

  def handle_call({:subscribe, topic, options}, _from, state) do
    %{
      conn: conn,
      client_id: client_id,
      sub_requests: sub_requests,
      subscriptions: subscriptions
    } = state

    # Subscribe to subscription's inbox.
    subscription = Subscription.new(topic: topic)
    Gnat.sub(conn, subscription.inbox, subscription.inbox_sid)

    # Make the subscription request.
    Logger.debug "->> SubscriptionRequest (#{topic})"
    subscription_request = Proto.subscription_request(subscription, client_id, options)
    {:ok, nats_msg} = Gnat.req_res(conn, sub_requests, subscription_request)
    response = SubscriptionResponse.new(nats_msg)
    subscription = put_in(subscription.ack_inbox, response.ack_inbox)
    Logger.debug "<<- SubscriptionResponse (#{topic})"

    # Record the subscription so we can match it up to the SubscriptionResponse.
    subscriptions = put_in(subscriptions, [topic], subscription)

    # :noreply so that the caller is blocked until we get the SubscriptionResponse.
    {:reply, :ok, %{state | subscriptions: subscriptions}}
  end

  def handle_call(:next_msg, _from, state) do
    %{msg_protos: msg_protos} = state
    msg_proto = List.last(msg_protos)
    msg_protos = List.delete_at(msg_protos, -1)
    {:reply, msg_proto, %{state | msg_protos: msg_protos}}
  end

  def handle_call({:ack, msg_proto}, _from, state) do
    %{conn: conn, subscriptions: subscriptions} = state

    # Find the corresponding subscription.
    subscription = subscriptions[msg_proto.subject]

    # Send the ack.
    ack_payload = Proto.ack(msg_proto.subject, msg_proto.sequence)
    Gnat.pub(conn, subscription.ack_inbox, ack_payload)

    # Log something nice.
    Logger.debug "->> Ack (#{msg_proto.subject}, #{msg_proto.sequence})"

    {:reply, :ok, state}
  end

  def handle_call({:publish, topic, data, options}, _from, state) do
    %{
      conn: conn,
      pub_prefix: pub_prefix,
      client_id: client_id,
    } = state

    # Log something nice.
    Logger.debug "->> PubMsg (#{topic}): #{data}"

    # Generate out payload.
    {_guid, pub_msg} = Proto.pub_msg(client_id, topic, data)

    # NATS subject... I think this is right.
    nats_subject = "#{pub_prefix}.#{topic}"

    if options[:ack] do
      # Request/response because we want the ack.
      {:ok, nats_msg} = Gnat.req_res(conn, nats_subject, pub_msg)
      ack = PubAck.new(nats_msg)
      Logger.debug("<<- PubAck (#{ack.guid})")
    else
      # Send the publish message without waiting for an ack.
      Gnat.pub(conn, nats_subject, pub_msg)
    end

    {:reply, :ok, state}
  end

  def handle_info({:nats_msg, nats_msg}, state) do
    Proto.parse(nats_msg) |> handle_message(state)
  end

  def handle_message(%Heartbeat{nats_msg: nats_msg}, state) do
    Logger.debug("<<- Heartbeat")
    Gnat.pub(state.conn, nats_msg.reply_to, "")
    Logger.debug("->> Pulse")
    {:noreply, state}
  end

  def handle_message(%MsgProto{} = msg_proto, state) do
    Logger.debug "<<- MsgProto (#{msg_proto.subject}): #{msg_proto.data}"
    if state.deliver_to do
      send(state.deliver_to, {:nats_stream_msg, msg_proto})
      {:noreply, state}
    else
      %{msg_protos: msg_protos} = state
      msg_protos = [msg_proto | msg_protos]
      {:noreply, %{state | msg_protos: msg_protos}}
    end
  end

end
