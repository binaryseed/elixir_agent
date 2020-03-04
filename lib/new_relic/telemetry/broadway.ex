defmodule NewRelic.Telemetry.Broadway do
  use GenServer

  @moduledoc """
  """

  def start_link() do
    GenServer.start_link(__MODULE__, :ok)
  end

  @handler_id {:new_relic, :broadway}

  @message_start [:broadway, :processor, :message, :start]
  @message_stop [:broadway, :processor, :message, :stop]
  @events [
    [:broadway, :processor, :start],
    [:broadway, :processor, :stop],
    @message_start,
    @message_stop,
    [:broadway, :processor, :message, :failure]
  ]
  def init(:ok) do
    config = %{handler_id: @handler_id}

    :telemetry.attach_many(
      @handler_id,
      @events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(@message_start, _, %{name: name}, _config) do
    IO.puts(">>>> START")
    NewRelic.start_transaction("Broadway", inspect(name))
  end

  def handle_event(@message_stop, _, _, _config) do
    IO.puts(">>>> COMPLETE")
    NewRelic.stop_transaction()
  end

  def handle_event(event, measurements, metadata, _config) do
    # IO.inspect({:telemetry, %{event: event, meas: measurements, metadata: metadata}})
  end
end
