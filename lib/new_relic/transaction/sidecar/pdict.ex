defmodule NewRelic.Transaction.Sidecar.Pdict do
  def init() do
    :ets.new(__MODULE__.LookupStore, [:named_table, :set, :public, read_concurrency: true])
  end

  def cleanup(pid) do
    IO.inspect({LookupStore, self(), :delete, pid})
    :ets.delete(__MODULE__.LookupStore, pid)
  end

  def set_sidecar(nil) do
    nil
  end

  def set_sidecar(:no_track) do
    :seq_trace.set_token([])
  end

  def set_sidecar(pid) do
    # Process.put(:nr_tx_sidecar, pid)
    :seq_trace.set_token(:label, {:nr_tx_sidecar, pid})
  end

  def get_sidecar() do
    :seq_trace.get_token(:label)
    |> IO.inspect(label: "label")
    |> case do
      {:label, {:nr_tx_sidecar, pid}} -> pid
      _ -> nil
    end

    # case Process.get(:nr_tx_sidecar) do
    #   nil ->
    #     sidecar =
    #       lookup_sidecar_in(process_callers()) ||
    #         lookup_sidecar_in(process_ancestors())

    #     set_sidecar(sidecar)

    #   :no_track ->
    #     nil

    #   pid ->
    #     pid
    # end
  end

  def store_sidecar(_, nil), do: :no_sidecar

  def store_sidecar(pid, sidecar) do
    IO.inspect({LookupStore, self(), :store, {pid, sidecar}})
    :ets.insert(__MODULE__.LookupStore, {pid, sidecar})
  end

  def lookup_sidecar(pid) when is_pid(pid) do
    IO.inspect({LookupStore, self(), :lookup, pid})

    case :ets.lookup(__MODULE__.LookupStore, pid) do
      [{_, sidecar}] -> sidecar
      [] -> nil
    end
  end

  def lookup_sidecar(_named_process), do: nil

  defp lookup_sidecar_in(processes) do
    Enum.find_value(processes, &lookup_sidecar/1)
  end

  defp process_callers() do
    Process.get(:"$callers", []) |> Enum.reverse()
  end

  defp process_ancestors() do
    Process.get(:"$ancestors", [])
  end
end
