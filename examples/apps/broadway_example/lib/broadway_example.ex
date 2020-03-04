defmodule BroadwayExample do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayExample.CounterProducer, 1}
      ],
      processors: [
        default: [concurrency: 1]
      ],
      batchers: [
        default: [concurrency: 1, batch_size: 2, batch_timeout: 1000]
      ]
    )
  end

  def handle_message(_processor_name, message, _context) do
    IO.puts("---- handle_message")

    message
    |> Broadway.Message.put_batcher(:default)
  end

  def handle_batch(:default, messages, _batch_info, _context) do
    # Send batch of messages to S3
    IO.puts("==== handle_batch #{length(messages)}")
    messages
  end
end
