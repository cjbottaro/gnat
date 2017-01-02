require Logger

# The whole handshake process is complicated enough to warrant factoring
# into its own module.
defmodule Gnat.Stream.Handshake do

  defmacro __using__(_opts) do
    quote bind_quoted: [module: __MODULE__] do

      @handshake_module module

      alias Gnat.Stream.Proto.ConnectResponse

      def handle_call(:wait_connect, from, state) do
        apply(@handshake_module, :handle_call, [:wait_connect, from, state])
      end

      def handle_message(%ConnectResponse{} = response, state) do
        apply(@handshake_module, :handle_message, [response, state])
      end

    end
  end

  def handle_call(:wait_connect, from, state) do
    if state.connected do
      {:reply, :ok, state}
    else
      {:noreply, %{state | connect_waiter: from}}
    end
  end

  def handle_message(%{error: error}, state) when not is_nil(error) do
    Logger.debug "<<- ConnectResponse ERROR: #{error}"
    if state.connect_waiter do
      GenServer.reply(state.connect_waiter, {:error, error})
      {:noreply, %{state | connect_waiter: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_message(response, state) do
    Logger.debug "<<- ConnectResponse"
    state = Map.merge(state, %{
      close_requests: response.close_requests,
      pub_prefix: response.pub_prefix,
      sub_close_requests: response.sub_close_requests,
      sub_requests: response.sub_requests,
      unsub_requests: response.unsub_requests,
      connected: true
    })
    if state.connect_waiter do
      GenServer.reply(state.connect_waiter, {:ok, self})
      {:noreply, %{state | connect_waiter: nil}}
    else
      {:noreply, state}
    end
  end

end
