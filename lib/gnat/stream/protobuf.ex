defmodule Gnat.Stream.Protobuf do
  use Protobuf, from: Path.expand("../../../streaming.proto", __DIR__)
end
