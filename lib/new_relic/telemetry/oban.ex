defmodule NewRelic.Telemetry.Oban do
  use GenServer

  @moduledoc """
  Provides `Oban` instrumentation via `telemetry`.

  Oban jobs are auto-discovered and instrumented.

  We automatically gather:

  * Transaction metrics and events
  * Transaction Traces
  * Distributed Traces

  You can opt-out of this instrumentation via configuration. See `NewRelic.Config` for details.
  """

  alias NewRelic.Transaction

  @doc false
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:oban_instrumentation),
      handler_id: {:new_relic, :oban}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @oban_start [:oban, :job, :start]
  @oban_stop [:oban, :job, :stop]
  @oban_exception [:oban, :job, :exception]

  @oban_events [
    @oban_start,
    @oban_stop,
    @oban_exception
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @oban_events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(
        @oban_start,
        %{system_time: system_time},
        meta,
        _config
      ) do
    Transaction.Reporter.start_transaction(:other)
    NewRelic.DistributedTrace.start(:other)

    add_start_attrs(meta, system_time)
  end

  def handle_event(
        @oban_stop,
        %{duration: duration} = meas,
        meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)

    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(
        @oban_exception,
        %{duration: duration} = meas,
        %{kind: kind} = meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)
    {reason, stack} = NewRelic.Util.Telemetry.reason_and_stack(meta)

    Transaction.Reporter.fail(%{kind: kind, reason: reason, stack: stack})
    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp add_start_attrs(meta, system_time) do
    [
      pid: inspect(self()),
      system_time: system_time,
      other_transaction_name: "Oban/#{meta.job.worker}/perform",
      "oban.state": meta.job.state,
      "oban.worker": meta.job.worker,
      "oban.queue": meta.job.queue,
      "oban.tags": meta.job.tags,
      "oban.attempt": meta.job.attempt,
      "oban.attempted_by": meta.job.attempted_by,
      "oban.max_attempts": meta.job.max_attempts,
      "oban.priority": meta.job.priority
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(meas, _meta, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions],
      "oban.queue_time": meas.queue_time
    ]
    |> NewRelic.add_attributes()
  end
end