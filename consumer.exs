defmodule Runner do

  def run do
    {:ok, pid} = Gnat.Stream.start_link(deliver_to: self())
    Gnat.Stream.subscribe(pid, "foo")
    loop(pid)
  end

  def loop(pid) do
    receive do
      {:nats_stream_msg, proto} ->
        IO.puts "#{proto.subject} -> #{proto.data}"
        Gnat.Stream.ack(pid, proto)
    end
    loop(pid)
  end

end

Logger.configure(level: :warn)
Runner.run
