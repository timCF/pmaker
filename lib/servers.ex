true = Application.get_env(:pmaker, :servers) |> Enum.all?(fn(%{module: module, app: main_app, port: port, kind: kind, decode: decode, encode: encode, crossdomain: crossdomain, callback_module: callback_module, priv_path: priv_path}) ->
	is_binary(module) and is_atom(main_app) and (main_app != nil) and is_integer(port) and (port > 0) and (kind in [:bullet, :cowboy]) and (decode in [nil, :json, :callback]) and (encode in [nil, :json, :callback]) and is_boolean(crossdomain) and is_atom(callback_module) and (callback_module != nil) and is_binary(priv_path)
end)

Application.get_env(:pmaker, :servers)
|> Enum.each(fn
	#
	#	BULLET
	#
	(fullconf = %{ module: module, app: main_app, port: port, kind: :bullet, decode: decode, encode: encode, crossdomain: crossdomain, callback_module: callback_module, priv_path: priv_path }) ->

		this_webhandler = String.to_atom("Elixir.Pmaker.Servers.#{module}.Handler")
		this_resourceloader = String.to_atom("Elixir.Pmaker.Servers.#{module}.ResourceLoader")
		this_webserver = String.to_atom("Elixir.Pmaker.Servers.#{module}.WebServer")

		defmodule this_resourceloader do
			require Pmaker
			Pmaker.resource_loader([main_app: unquote(main_app), priv_path: unquote(priv_path)])
		end

		defmodule this_webhandler do
			use Silverb
			require Logger
			@pg2 Pmaker.get_pg2(fullconf)
			@callback_module callback_module

			case decode do
				nil ->
					defp decode(some) do
						%Pmaker.Request{data: some}
					end
				:json ->
					defp decode(some) do
						case Jazz.decode(some) do
							{:ok, data} -> %Pmaker.Request{data: data}
							error -> %Pmaker.Request{ok: false, data: some, error: error}
						end
					end
				:callback ->
					defp decode(some) do
						case @callback_module.decode(some) do
							{:ok, data} -> %Pmaker.Request{data: data}
							{:error, error} -> %Pmaker.Request{ok: false, data: some, error: error}
						end
					end
				some ->
					raise("#{inspect some} decode protocol is not supported yet")
			end

			case encode do
				nil ->
					defp encode(some) do
						some
					end
				:json ->
					defp encode(some) do
						Jazz.encode!(some)
					end
				:callback ->
					defp encode(some) do
						@callback_module.encode(some)
					end
				some ->
					raise("#{inspect some} encode protocol is not supported yet")
			end

			def init(_Transport, req, _Opts, _Active) do
				:ok = :pg2.join(@pg2, self())
				{:ok, req, :undefined_state}
			end
			def stream(data, req, state) do
				data
				|> decode
				|> @callback_module.handle_pmaker
				|> info(req, state) # do reply tuple in next callback
			end
			def info(%Pmaker.Response{data: reply_data, encode: encode}, req, state) do
				{ :reply, (case encode do ; true -> encode(reply_data) ; false -> reply_data ; end), req, state }
			end
			def info(info, req, state) do
				Logger.error "#{__MODULE__} : unexpected info #{inspect info}"
				{:ok, req, state}
			end
			def terminate(_req, _state) do
				:ok = :pg2.leave(@pg2, self())
			end
		end

		defmodule this_webserver do
			use Silverb
			require Logger
			def start do
				dispatch = :cowboy_router.compile([
					{:_, [
						{"/bullet", :bullet_handler, [{:handler, unquote(this_webhandler)}]},
						{"/index.html", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/[...]", unquote(this_resourceloader), [nil]}
					]}])
				res = {:ok, _} = :cowboy.start_http(unquote(String.to_atom(module)), 5000, [port: unquote(port) ], [env: [ dispatch: dispatch ] ])
				Logger.info("HTTP BULLET server started at port #{ unquote(port) }")
				res
			end
		end

end)
