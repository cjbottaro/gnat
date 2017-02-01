Logger.configure(level: :info)

defmodule GnatStreamTest do
  use ExUnit.Case
  doctest Gnat

  def receive_and_ack(conn) do
    receive do
      {:nats_stream_msg, message} ->
        Gnat.Stream.ack(conn, message)
        message
    end
  end

  test "it generally works" do
    {:ok, conn} = Gnat.Stream.start_link(deliver_to: self(), client_id: "gnat_test")
    Gnat.Stream.subscribe(conn, "foo")
    messages = [
      SecureRandom.hex(16),
      SecureRandom.hex(16)
    ]
    Enum.each messages, fn message ->
      Gnat.Stream.publish(conn, "foo", message)
    end
    received_messages = [
      receive_and_ack(conn).data,
      receive_and_ack(conn).data
    ]
    assert messages == received_messages
    Gnat.Stream.close(conn)
  end
end
