require Logger

defmodule Gnat.Stream.Connection do
  use Connection
  use Gnat.Stream.Handshake

  alias Gnat.Stream.Proto
  alias Proto.{Heartbeat, ConnectResponse, SubscriptionResponse, MsgProto, PubAck}
  alias Gnat.Stream.Subscription

  def start_link(options) do
    Connection.start_link(__MODULE__, options)
  end

  def init(options) do
    {:ok, conn} = Gnat.start_link(options)
    Gnat.deliver_to(conn, self)

    state = options
      |> Enum.into(%{})
      |> Map.merge(%{
        conn: conn,
        connected: false,
        subscriptions: %{},
        msg_protos: [],
        connect_waiter: nil,
        pub_ack_waiters: %{}
      })

    {:connect, nil, state}
  end

  def terminate(reason, %{connected: true} = state) do
    %{conn: conn, client_id: client_id} = state
    if state.close_requests do
      Logger.debug "->> CloseRequest"
      Gnat.pub(conn, state.close_requests, Proto.close_request(client_id))
    end
    terminate(reason, %{state | connected: false})
  end
  def terminate(_, state) do
    GenServer.stop(state.conn)
  end

  def connect(_info, state) do
    %{
      conn: conn,
      client_id: client_id,
      cluster_id: cluster_id,
      discover_prefix: discover_prefix,
    } = state

    {:ok, heart_inbox, _sid} = Gnat.sub(conn, prefix: "Heartbeat")

    connect_request = Proto.connect_request(clientID: client_id, heartbeatInbox: heart_inbox)

    Gnat.req_res(conn,
      send_to: "#{discover_prefix}.#{cluster_id}",
      recv_at_prefix: "ConnectResponse",
      payload: connect_request
    )

    Logger.debug "->> ConnectRequest"

    {:ok, state}
  end

  def handle_call(:shutdown, _from, state) do
    {:stop, :normal, state}
  end

  def handle_call({:subscribe, topic, options}, from, state) do
    %{
      conn: conn,
      client_id: client_id,
      sub_requests: sub_requests,
      subscriptions: subscriptions
    } = state

    subscription = Subscription.new(topic: topic, blocker: from)
    subscription_request = Proto.subscription_request(subscription, client_id, options)

    # Subscribe to subscription's inbox.
    Gnat.sub(conn, subject: subscription.inbox, sid: subscription.inbox_sid)

    # Make the subscription request.
    Gnat.req_res(conn, send_to: sub_requests, recv_at: subscription.response_inbox, payload: subscription_request)
    Logger.debug "->> SubscriptionRequest (#{topic})"

    # Record the subscription so we can match it up to the SubscriptionResponse.
    subscriptions = Map.put(subscriptions, topic, subscription)

    # :noreply so that the caller is blocked until we get the SubscriptionResponse.
    {:noreply, %{state | subscriptions: subscriptions}}
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
    Gnat.pub(conn, subscription.ack_outbox, ack_payload)

    # Log something nice.
    Logger.debug "->> Ack (#{msg_proto.subject}, #{msg_proto.sequence})"

    {:reply, :ok, state}
  end

  def handle_call({:publish, topic, data, options}, from, state) do
    %{
      conn: conn,
      pub_prefix: pub_prefix,
      client_id: client_id,
    } = state

    # Log something nice.
    Logger.debug "->> PubMsg (#{topic}): #{data}"

    # Generate out payload.
    {guid, pub_msg} = Proto.pub_msg(client_id, topic, data)

    # NATS subject... I think this is right.
    nats_subject = "#{pub_prefix}.#{topic}"

    if options[:ack] do
      # Request/response because we want the ack.
      Gnat.req_res(conn, send_to: nats_subject, recv_at_prefix: "PubAck", payload: pub_msg)

      # Update our pub ack waiters.
      %{pub_ack_waiters: pub_ack_waiters} = state
      pub_ack_waiters = Map.put(pub_ack_waiters, guid, from)

      {:noreply, %{state | pub_ack_waiters: pub_ack_waiters}}
    else
      # Send the publish message without a reply to.
      Gnat.pub(conn, nats_subject, pub_msg)

      {:reply, :ok, state}
    end
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

  def handle_message(%SubscriptionResponse{} = response, state) do
    # Make some local vars.
    %{subscriptions: subscriptions} = state

    # Find the subscription.
    {_, subscription} = Enum.find(subscriptions, fn {_, subscription} ->
      response.nats_msg.subject == subscription.response_inbox
    end)

    # Log something nice.
    Logger.debug "<<- SubscriptionResponse (#{subscription.topic})"

    # Record in our subscription where to send acks.
    subscription = Map.put(subscription, :ack_outbox, response.ack_inbox)

    # Update our subscriptions.
    subscriptions = %{subscriptions | subscription.topic => subscription}

    # Notify the caller (who is blocking).
    GenServer.reply(subscription.blocker, :ok)

    {:noreply, %{state | subscriptions: subscriptions}}
  end

  def handle_message(%MsgProto{} = msg_proto, state) do
    Logger.debug "<<- MsgProto (#{msg_proto.subject}): #{msg_proto.data}"
    if state.deliver_to do
      send(state.deliver_to, {:nats_streaming_msg, msg_proto})
      {:noreply, state}
    else
      %{msg_protos: msg_protos} = state
      msg_protos = [msg_proto | msg_protos]
      {:noreply, %{state | msg_protos: msg_protos}}
    end
  end

  def handle_message(%PubAck{} = pub_ack, state) do
    %{pub_ack_waiters: pub_ack_waiters} = state
    %{guid: guid} = pub_ack

    # Log something nice.
    Logger.debug "<<- PubAck (#{guid})"

    # Get the waiter and update our waiters.
    {waiter, pub_ack_waiters} = Map.pop(pub_ack_waiters, guid)

    # Unblock them!
    GenServer.reply(waiter, :ok)

    {:noreply, %{state | pub_ack_waiters: pub_ack_waiters}}
  end

end
