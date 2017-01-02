defmodule Gnat.Stream do

  @defaults [
    host: "localhost",
    port: 4222,
    cluster_id: "test-cluster",
    client_id: "gnat",
    discover_prefix: "_STAN.discover",
    deliver_to: nil
  ]
  def start_link(options \\ []) do
    options = Keyword.merge(@defaults, options)
    case Gnat.Stream.Connection.start_link(options) do
      {:ok, pid} -> stream_connect_protocol(pid)
      res -> res
    end
  end

  @defaults [
    max_in_flight: 1,
    ack_wait_in_secs: 30,
    start_position: :first
  ]
  def subscribe(pid, topic, options \\ []) do
    options = Keyword.merge(@defaults, options)
    GenServer.call(pid, {:subscribe, topic, options})
  end

  def next_msg(pid) do
    GenServer.call(pid, :next_msg)
  end

  def ack(pid, msg_proto) do
    GenServer.call(pid, {:ack, msg_proto})
  end

  @defaults [
    ack: true
  ]
  def publish(pid, topic, data, options \\ []) do
    options = Keyword.merge(@defaults, options)
    GenServer.call(pid, {:publish, topic, data, options}, :infinity)
  end

  defp stream_connect_protocol(pid) do
    try do
      case GenServer.call(pid, :wait_connect) do
        {:error, _} = res ->
          IO.puts "stopping"
          GenServer.stop(pid)
          res
        res -> res
      end
    catch
      :exit, _ ->
        GenServer.stop(pid)
        {:error, :timeout}
    end
  end

end
