defmodule Gnat.Buffer do
  @moduledoc false
  
  def process(buffer, messages \\ []) do
    {message, buffer} = process_single(buffer)
    if message do
      process(buffer, [message | messages])
    else
      {messages, buffer}
    end
  end

  defp process_single(buffer) do
    case String.split(buffer, "\r\n", parts: 2) do
      [part | []] -> {nil, part}
      [message, rest | []] -> parse(message, rest)
    end
  end

  defp parse(message, rest) do
    if String.starts_with?(message, "MSG ") do
      parse_multi_line(message, rest)
    else
      {message, rest}
    end
  end

  defp parse_multi_line(header, rest) do
    case String.split(header, " ") do
      [_op, _subject, _sid, _reply_to, bytes | []] ->
        parse_multi_line(header, rest, bytes)
      [_op, _subject, _sid, bytes | []] ->
        parse_multi_line(header, rest, bytes)
    end
  end

  defp parse_multi_line(header, rest, bytes) do
    bytes = String.to_integer(bytes)

    if byte_size(rest) < bytes+2 do # +2 for the \r\n
      {nil, "#{header}\r\n#{rest}"}
    else
      payload = binary_part(rest, 0, bytes)
      rest = binary_part(rest, bytes+2, byte_size(rest)-bytes-2) # Skip the \r\n
      {"#{header}\r\n#{payload}", rest}
    end
  end

end
