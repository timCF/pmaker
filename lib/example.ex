defmodule Pmaker.Example do
	defmodule Bullet do
		# just echo
		def handle_pmaker(%Pmaker.Request{data: data}) do
			%Pmaker.Response{data: data}
		end
	end
end
