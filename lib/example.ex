defmodule Pmaker.Example do
	defmodule Bullet do
		def handle_pmaker(%Pmaker.Request{data: data, ok: true}) do
			%Pmaker.Response{data: data}
		end
	end
	defmodule Cowboy do
		def handle_pmaker(%Pmaker.Request{qs: qs, data: data}) when (qs != %{}) do
			%Pmaker.Response{data: %{postdata: data, qs: qs}}
		end
		def handle_pmaker(%Pmaker.Request{data: data}) do
			%Pmaker.Response{data: data}
		end
		def decode(some) do
			IO.puts("pass decoding #{inspect some}")
			{:ok, some}
		end
		def encode(some = %{}) do
			IO.puts("encoding #{inspect some}")
			Jazz.encode!(some)
		end
		def encode(some) do
			IO.puts("pass encoding #{inspect some}")
			some
		end
	end
end
