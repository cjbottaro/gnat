Logger.configure(level: :info)

defmodule GnatTest do
  use ExUnit.Case
  doctest Gnat

  test "that we can connect" do
    {:ok, conn} = Gnat.start_link
    info = Gnat.info(conn)
    assert is_map(info)
    assert String.length(info.server_id) > 0
    Gnat.close(conn)
  end

  test "pub sub" do
    {:ok, conn} = Gnat.start_link(deliver_to: self)
    Gnat.sub(conn, "foo", Gnat.new_sid)
    Gnat.pub(conn, "foo", "bar")
    msg = receive do
      {:nats_msg, msg} -> msg
    end
    assert msg.payload == "bar"
    Gnat.close(conn)
  end

  test "next_msg" do
    {:ok, conn} = Gnat.start_link
    Gnat.sub(conn, "foo", Gnat.new_sid)
    Gnat.pub(conn, "foo", "bar")
    Process.sleep(10) # Forgive me.
    msg = Gnat.next_msg(conn)
    assert msg.payload == "bar"
    assert Gnat.next_msg(conn) == nil
  end

  test "req_rpl" do
    server = Task.async fn ->
      {:ok, conn} = Gnat.start_link(deliver_to: self)
      Gnat.sub(conn, "foo", Gnat.new_sid)
      receive do
        {:nats_msg, msg} ->
          Gnat.pub(conn, msg.reply_to, "#{msg.payload}!")
      end
      Gnat.close(conn)
    end

    {:ok, conn} = Gnat.start_link(deliver_to: self)
    {:ok, msg} = Gnat.req_rpl(conn, "foo", "bar")
    assert msg.payload == "bar!"
    Gnat.close(conn)

    Task.await(server)
  end

  test "unsub" do
    {:ok, conn} = Gnat.start_link
    sid = Gnat.new_sid
    Gnat.sub(conn, "foo", sid)
    Gnat.unsub(conn, sid, max_msgs: 2)
    Gnat.pub(conn, "foo", "one")
    Gnat.pub(conn, "foo", "two")
    Gnat.pub(conn, "foo", "three")
    Process.sleep(10) # Forgive me again.
    messages = [
      Gnat.next_msg(conn).payload,
      Gnat.next_msg(conn).payload,
      Gnat.next_msg(conn)
    ]
    assert Enum.sort(messages) == [nil, "one", "two"]
    Gnat.close(conn)
  end

end
