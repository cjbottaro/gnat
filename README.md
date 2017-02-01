# Gnat

Connect to and interact with NATS and/or NATS Streaming servers.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `gnat` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:gnat, "~> 0.1.0"}]
    end
    ```

  2. Ensure `gnat` is started before your application:

    ```elixir
    def application do
      [applications: [:gnat]]
    end
    ```

## Features

  * Documentation
    * [NATS](Gnat.html)
    * [NATS Streaming](Gnat.Stream.html)
  * NATS Streaming
  * Request/reply API

## Server Version Requirements

  * NATS >= 0.9.0 (I think)
  * NATS Streaming >= 0.3.7

## Quickstart - NATS

```elixir
{:ok, conn} = Gnat.start_link(deliver_to: self())
Gnat.sub(conn, "foo", "sid123")
Gnat.pub(conn, "foo", "hello!")
receive do
  {:nats_msg, msg} -> IO.puts "#{msg.subject}: #{msg.payload}"
end
Gnat.close(conn)
```

## Quickstart - NATS Streaming

```elixir
{:ok, conn} = Gnat.Stream.start_link(deliver_to: self())
Gnat.Stream.subscribe(conn, "foo")
Gnat.Stream.publish(conn, "foo", "hello!")
receive do
  {:nats_stream_msg, msg} ->
    IO.puts "#{msg.subject}: #{msg.data}"
    Gnat.Stream.ack(conn, msg)
end
Gnat.Stream.close(conn)
```

## Request/Reply

The NATS protocol allows for [request/reply messaging](https://nats.io/documentation/concepts/nats-req-rep/).

`Gnat` makes this very easy to use with `Gnat.request/3`. We can demonstrate by
writing a echo server.

Server
```elixir
{:ok, conn} = Gnat.start_link(deliver_to: self())
Gnat.sub(conn, "echo", Gnat.new_sid)
Stream.repeatedly(fn ->
  receive do
    {:nats_msg, msg} -> msg
  end
end) |> Enum.each(fn msg ->
  Gnat.pub(conn, msg.reply_to, msg.payload)
end)
```

Client
```elixir
{:ok, conn} = Gnat.start_link
{:ok, reply} = Gnat.request(conn, "echo", "hello")
IO.puts reply.payload # => "hello"
{:ok, res} = Gnat.request(conn, "echo", "goodbye")
IO.puts reply.payload # => "goodbye"
Gnat.close(conn)
```

## TODO

  * Authentication
  * one-to-many request/reply
