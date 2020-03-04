defmodule BroadwayExample.CounterProducer do
  use GenStage

  def init(counter) do
    {:producer, counter}
  end

  def handle_demand(demand, counter) when demand > 0 do
    events =
      Enum.to_list(counter..(counter + demand - 1))
      |> Enum.map(
        &%Broadway.Message{
          data: &1,
          acknowledger: {__MODULE__, :ack_id, :ack_data}
        }
      )

    Process.sleep(1000)

    {:noreply, events, counter + demand}
  end

  def ack(:ack_id, _successful, _failed) do
    :ok
  end
end
