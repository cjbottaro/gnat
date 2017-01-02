defmodule Gnat.Stream.Proto do

  alias Gnat.Stream.Protobuf
  alias __MODULE__.{Heartbeat, ConnectResponse, SubscriptionResponse, MsgProto, PubAck}

  defmacro __using__(_) do
    quote do
      name = __MODULE__ |> Atom.to_string |> String.split(".") |> List.last
      attributes = "Elixir.Gnat.Stream.Protobuf.#{name}"
        |> String.to_atom
        |> apply(:record, [])
        |> Keyword.keys
        |> Enum.map(fn attribute ->
          attribute
            |> Atom.to_string
            |> Macro.underscore
            |> String.to_atom
        end)
      defstruct [:nats_msg | attributes]

      def new(nats_msg) do
        # Get the protobuf module.
        name = __MODULE__ |> Atom.to_string |> String.split(".") |> List.last
        protobuf_module = "Elixir.Gnat.Stream.Protobuf.#{name}" |> String.to_atom

        # Decode the protobuf and turn into a map.
        record = apply(protobuf_module, :decode, [nats_msg.payload])
          |> Map.from_struct

        # Underscore the attributes.
        attributes = Enum.map(record, fn {k, v} ->
          {k |> Atom.to_string |> Macro.underscore |> String.to_atom, v}
        end)

        # Put the nats message in.
        attributes = Keyword.put(attributes, :nats_msg, nats_msg)

        struct!(__MODULE__, attributes)
      end
    end
  end

  def parse(nats_msg) do
    cond do
      subject_prefix?(nats_msg, "Heartbeat") ->
        Heartbeat.new(nats_msg)
      subject_prefix?(nats_msg, "ConnectResponse") ->
        ConnectResponse.new(nats_msg)
      subject_prefix?(nats_msg, "SubscriptionResponse") ->
        SubscriptionResponse.new(nats_msg)
      subject_prefix?(nats_msg, "MsgProto") ->
        MsgProto.new(nats_msg)
      subject_prefix?(nats_msg, "PubAck") ->
        PubAck.new(nats_msg)
    end
  end

  def connect_request(options \\ []) do
    alias Protobuf.ConnectRequest
    ConnectRequest.new(options) |> ConnectRequest.encode
  end

  def subscription_request(subscription, client_id, options) do
    alias Protobuf.SubscriptionRequest
    import Gnat.Stream.Subscription, only: [start_position: 1]

    start_position = start_position(options[:start_position])

    SubscriptionRequest.new(
      clientID: client_id,
      subject: subscription.topic,
      inbox: subscription.inbox,
      maxInFlight: options[:max_in_flight],
      ackWaitInSecs: options[:ack_wait_in_secs],
      startPosition: start_position
    ) |> SubscriptionRequest.encode
  end

  def ack(subject, sequence) do
    alias Protobuf.Ack
    Ack.new(subject: subject, sequence: sequence) |> Ack.encode
  end

  def pub_msg(client_id, subject, data, options \\ []) do
    alias Protobuf.PubMsg
    guid = SecureRandom.hex(15) # Anything longer will cause a PubAck protobuf message that won't parse.
    pub_msg = PubMsg.new(
      clientID: client_id,
      guid: guid,
      subject: subject,
      data: data,
      reply: options[:reply],
      sha256: options[:sha256]
    ) |> PubMsg.encode
    {guid, pub_msg}
  end

  def close_request(client_id) do
    alias Protobuf.CloseRequest
    CloseRequest.new(clientID: client_id) |> CloseRequest.encode
  end

  defp subject_prefix?(nats_msg, prefix) do
    String.starts_with?(nats_msg.subject, "#{prefix}.")
  end

end
