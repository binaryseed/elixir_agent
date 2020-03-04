defmodule BroadwayExampleTest do
  use ExUnit.Case
  doctest BroadwayExample

  test "greets the world" do
    assert BroadwayExample.hello() == :world
  end
end
