defmodule NewRelic.Error.LoggerHandler do
  @moduledoc false

  # http://erlang.org/doc/man/logger.html

  def add_handler() do
    :logger.remove_handler(:new_relic)
    :logger.add_handler(:new_relic, NewRelic.Error.LoggerHandler, %{})
  end

  def remove_handler() do
    :logger.remove_handler(:new_relic)
  end

  def log(
        %{
          level: level,
          meta: %{error_logger: %{tag: :error_report, type: :crash_report}} = erl_meta,
          msg: {:report, %{label: label, report: [report | _] = full_report}}
        } = log,
        _config
      ) do
    {chardata, _} =
      Logger.ErlangHandler.translate(level, :report, {label, full_report}, [], erl_meta)

    IO.puts(">>>>>>>>>>>>>>>>")
    IO.puts(chardata)
    IO.puts(">>>>>>>>>>>>>>>>")

    if NewRelic.Transaction.Reporter.tracking?(self()) do
      NewRelic.Error.Reporter.report_error(:transaction, report)
    else
      NewRelic.Error.Reporter.report_error(:process, report)
    end
  end

  def log(_log, _config), do: :ignore
end
