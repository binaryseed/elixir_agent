defmodule NewRelic.Transaction.Reporter do
  alias NewRelic.Transaction

  # This GenServer collects and reports Transaction related data
  #  - Transaction Events
  #  - Transaction Metrics
  #  - Span Events
  #  - Transaction Errors
  #  - Transaction Traces
  #  - Custom Attributes

  @moduledoc false

  # Customer Exposed functions

  def add_attributes(attrs) when is_list(attrs) do
    attrs
    |> NewRelic.Util.deep_flatten()
    |> NewRelic.Util.coerce_attributes()
    |> Transaction.Sidecar.add()
  end

  def incr_attributes(attrs) do
    Transaction.Sidecar.incr(attrs)
  end

  def set_transaction_name(custom_name) when is_binary(custom_name) do
    Transaction.Sidecar.add(custom_name: custom_name)
  end

  # Internal Agent functions

  def start_transaction(:web) do
    Transaction.ErlangTrace.trace()
    Transaction.Sidecar.track(:web)
  end

  def start_transaction(:other) do
    unless Transaction.Sidecar.tracking?() do
      Transaction.ErlangTrace.trace()
      Transaction.Sidecar.track(:other)
    end
  end

  def stop_transaction(:web) do
    Transaction.Sidecar.complete()
  end

  def stop_transaction(:other) do
    Transaction.Sidecar.add(end_time_mono: System.monotonic_time())
    Transaction.Sidecar.complete()
  end

  def ignore_transaction() do
    Transaction.Sidecar.ignore()
  end

  def exclude_from_transaction() do
    Transaction.Sidecar.exclude()
  end

  def error(error) do
    Transaction.Sidecar.add(transaction_error: {:error, error})
  end

  def fail(%{kind: kind, reason: reason, stack: stack}) do
    if NewRelic.Config.feature?(:error_collector) do
      Transaction.Sidecar.add(
        error: true,
        error_kind: kind,
        error_reason: inspect(reason),
        error_stack: inspect(stack)
      )
    else
      Transaction.Sidecar.add(error: true)
    end
  end

  def add_trace_segment(segment) do
    Transaction.Sidecar.add(function_segments: {:list, segment})
  end

  def track_metric(metric) do
    Transaction.Sidecar.add(transaction_metrics: {:list, metric})
  end

  def track_spawn(parent, child, timestamp) do
    Transaction.Sidecar.track_spawn(parent, child, timestamp)
  end
end
