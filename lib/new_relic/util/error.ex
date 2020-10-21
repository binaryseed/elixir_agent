defmodule NewRelic.Util.Error do
  # Helper functions for normalizing and formatting errors

  @moduledoc false

  def normalize(kind, exception, stacktrace, initial_call \\ nil)

  def normalize(kind, exception, stacktrace, initial_call) do
    normalized_error = Exception.normalize(kind, exception, stacktrace)

    exception_type = format_type(kind, normalized_error)
    exception_reason = format_reason(kind, normalized_error)
    exception_stacktrace = format_stacktrace(stacktrace, initial_call)

    {exception_type, exception_reason, exception_stacktrace}
  end

  def format_type(:error, %ErlangError{original: {_reason, {module, function, args}}}),
    do: Exception.format_mfa(module, function, length(args))

  def format_type(:error, %{__struct__: struct}), do: inspect(struct)
  def format_type(:exit, _reason), do: "EXIT"

  def format_reason(:error, %ErlangError{original: {reason, {module, function, args}}}),
    do: "(" <> Exception.format_mfa(module, function, length(args)) <> ") " <> inspect(reason)

  def format_reason(:error, error),
    do:
      :error
      |> Exception.format_banner(error)
      |> String.replace("** ", "")

  def format_reason(:exit, {reason, {module, function, args}}),
    do: "(" <> Exception.format_mfa(module, function, length(args)) <> ") " <> inspect(reason)

  def format_reason(:exit, %{__exception__: true} = error), do: format_reason(:error, error)
  def format_reason(:exit, reason), do: inspect(reason)

  def format_stacktrace(stacktrace, initial_call),
    do:
      List.wrap(stacktrace)
      |> prepend_initial_call(initial_call)
      |> Enum.map(&Exception.format_stacktrace_entry/1)

  defp prepend_initial_call(stacktrace, {mod, fun, args}),
    do: stacktrace ++ [{mod, fun, args, []}]

  defp prepend_initial_call(stacktrace, _), do: stacktrace
end
