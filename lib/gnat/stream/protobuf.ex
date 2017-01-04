defmodule Gnat.Stream.Protobuf do
  @moduledoc false
  
  use Protobuf, from: Path.expand("../../../streaming.proto", __DIR__)
end
