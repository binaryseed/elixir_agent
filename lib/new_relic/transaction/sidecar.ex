defmodule NewRelic.Transaction.Sidecar do
  @moduledoc false
  use GenServer, restart: :temporary

  def setup_stores do
    :ets.new(__MODULE__.ContextStore, [:named_table, :set, :public, read_concurrency: true])
    NewRelic.Transaction.Sidecar.Pdict.init()
    :persistent_term.put({__MODULE__, :counter}, :counters.new(1, []))
  end

  def track(type) do
    # We use `GenServer.start` to avoid a bi-directional link
    # and guarentee that we never crash the Transaction process
    # even in the case of an unexpected bug. Additionally, this
    # blocks the Transaction process the smallest amount possible
    {:ok, sidecar} = GenServer.start(__MODULE__, {self(), type})
    IO.inspect({:start, self(), %{sidecar: sidecar}})

    store_sidecar(self(), sidecar)

    receive do
      :sidecar_ready -> :ok
    end

    set_sidecar(sidecar)
  end

  def init({parent, type}) do
    Process.monitor(parent)
    send(parent, :sidecar_ready)
    counter(:add)

    {:ok,
     %{
       start_time: System.system_time(:millisecond),
       type: type,
       parent: parent,
       exclusions: [],
       offspring: MapSet.new(),
       attributes: []
     }}
  end

  def connect(pid) do
    set_sidecar(lookup_sidecar(pid))
    cast({:add_offspring, self()})
  end

  def disconnect() do
    set_sidecar(:no_track)
  end

  def tracking?() do
    is_pid(get_sidecar())
  end

  def track_spawn(parent, child, timestamp) do
    parent_sidecar = lookup_sidecar(parent)
    store_sidecar(child, parent_sidecar)
    cast(parent_sidecar, {:spawn, parent, child, timestamp})
  end

  def add(attrs) do
    cast({:add_attributes, attrs})
  end

  def incr(attrs) do
    attrs
    |> wrap(:counter)
    |> add()
  end

  def append(attrs) do
    attrs
    |> wrap(:list)
    |> add()
  end

  def trace_context(context) do
    :ets.insert(__MODULE__.ContextStore, {{:context, get_sidecar()}, context})
  end

  def trace_context() do
    case :ets.lookup(__MODULE__.ContextStore, {:context, get_sidecar()}) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  def ignore() do
    cast(:ignore)
    set_sidecar(:no_track)
  end

  def exclude() do
    cast({:exclude, self()})
    set_sidecar(:no_track)
  end

  def complete() do
    with sidecar when is_pid(sidecar) <- get_sidecar() do
      cleanup(context: sidecar)
      cleanup(lookup: self())
      clear_sidecar()
      cast(sidecar, :complete)
    else
      nope -> IO.inspect({:COMPLETE, :nope, nope})
    end
  end

  defp cast(message) do
    GenServer.cast(get_sidecar(), message)
  end

  defp cast(sidecar, message) do
    GenServer.cast(sidecar, message)
  end

  def handle_cast({:add_attributes, attrs}, state) do
    {:noreply, %{state | attributes: attrs ++ state.attributes}}
  end

  def handle_cast({:spawn, _parent, _child, timestamp}, %{start_time: start_time} = state)
      when timestamp < start_time do
    {:noreply, state}
  end

  def handle_cast({:spawn, parent, child, timestamp}, state) do
    Process.monitor(child)

    spawn_attrs = [
      process_spawns: {:list, {child, timestamp, parent, NewRelic.Util.process_name(child)}}
    ]

    {:noreply,
     %{
       state
       | attributes: spawn_attrs ++ state.attributes,
         offspring: MapSet.put(state.offspring, child)
     }}
  end

  def handle_cast({:exclude, pid}, state) do
    {:noreply, %{state | exclusions: [pid | state.exclusions]}}
  end

  def handle_cast({:add_offspring, pid}, state) do
    {:noreply, %{state | offspring: MapSet.put(state.offspring, pid)}}
  end

  def handle_cast(:ignore, state) do
    cleanup(context: self())
    IO.inspect({:ignore, LookupStore, state.parent})
    cleanup(lookup: state.parent)
    {:stop, :normal, state}
  end

  def handle_cast(:complete, state) do
    {:noreply, state, {:continue, :complete}}
  end

  def handle_info(
        {:DOWN, _, _, parent, down_reason},
        %{type: :other, parent: parent} = state
      ) do
    attributes = state.attributes

    attributes =
      with {reason, stack} when reason != :shutdown <- down_reason do
        error_attrs = [
          error: true,
          error_kind: :exit,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        ]

        error_attrs ++ attributes
      else
        _ -> attributes
      end

    attributes = Keyword.put_new(attributes, :end_time_mono, System.monotonic_time())

    {:noreply, %{state | attributes: attributes}, {:continue, :complete}}
  end

  def handle_info({:DOWN, _, _, child, _}, state) do
    exit_attrs = [process_exits: {:list, {child, System.system_time(:millisecond)}}]

    {:noreply, %{state | attributes: exit_attrs ++ state.attributes}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def handle_continue(:complete, state) do
    cleanup(context: self())
    Enum.each(state.offspring, &cleanup(lookup: &1))
    run_complete(state)
    counter(:sub)
    report_stats()
    {:stop, :normal, :completed}
  end

  @kb 1024
  defp report_stats() do
    info = Process.info(self(), [:memory, :reductions])

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Process/MemoryKb"},
      value: info[:memory] / @kb
    )

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Process/Reductions"},
      value: info[:reductions]
    )
  end

  defp clear_sidecar() do
    # Process.delete(:nr_tx_sidecar)
    :seq_trace.set_token([])
  end

  defp set_sidecar(pid) do
    NewRelic.Transaction.Sidecar.Pdict.set_sidecar(pid)
  end

  defp get_sidecar() do
    NewRelic.Transaction.Sidecar.Pdict.get_sidecar()
  end

  defp store_sidecar(pid, sidecar) do
    NewRelic.Transaction.Sidecar.Pdict.store_sidecar(pid, sidecar)
  end

  defp lookup_sidecar(pid) when is_pid(pid) do
    NewRelic.Transaction.Sidecar.Pdict.lookup_sidecar(pid)
  end

  defp cleanup(context: sidecar) do
    :ets.delete(__MODULE__.ContextStore, {:context, sidecar})
  end

  defp cleanup(lookup: root) do
    NewRelic.Transaction.Sidecar.Pdict.cleanup(root)
  end

  def counter() do
    :counters.get(:persistent_term.get({__MODULE__, :counter}), 1)
  end

  defp counter(:add) do
    :counters.add(:persistent_term.get({__MODULE__, :counter}), 1, 1)
  end

  defp counter(:sub) do
    :counters.sub(:persistent_term.get({__MODULE__, :counter}), 1, 1)
  end

  defp run_complete(%{attributes: attributes} = state) do
    attributes
    |> Enum.reverse()
    |> Enum.reject(&exclude_attrs(&1, state.exclusions))
    |> Enum.reduce(%{}, &collect_attr/2)
    |> NewRelic.Transaction.Complete.run(state.parent)
  end

  defp wrap(attrs, tag) do
    Enum.map(attrs, fn {key, value} -> {key, {tag, value}} end)
  end

  defp exclude_attrs({:process_spawns, {:list, {pid, _, _, _}}}, exclusions),
    do: pid in exclusions

  defp exclude_attrs(_, _), do: false

  defp collect_attr({k, {:list, item}}, acc), do: Map.update(acc, k, [item], &[item | &1])
  defp collect_attr({k, {:counter, n}}, acc), do: Map.update(acc, k, n, &(&1 + n))
  defp collect_attr({k, v}, acc), do: Map.put(acc, k, v)
end
