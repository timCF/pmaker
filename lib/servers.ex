true = Application.get_env(:pmaker, :servers) |> Enum.all?(fn(%{module: module, app: main_app, port: port, kind: kind, decode: decode, encode: encode, crossdomain: crossdomain, callback_module: callback_module, priv_path: priv_path}) ->
	is_binary(module) and is_atom(main_app) and (main_app != nil) and is_integer(port) and (port > 0) and (kind in [:bullet, :cowboy]) and (decode in [nil, :json, :callback]) and (encode in [nil, :json, :callback]) and is_boolean(crossdomain) and is_atom(callback_module) and (callback_module != nil) and is_binary(priv_path)
end)

Application.get_env(:pmaker, :servers)
|> Enum.each(fn

	##########
	# BULLET #

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
			require Pmaker
			@pg2 Pmaker.get_pg2(fullconf)
			@callback_module callback_module

			Pmaker.decode_macro([decode: decode])
			Pmaker.encode_macro([encode: encode])

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
				_ = Logger.error("#{__MODULE__} : unexpected info #{inspect info}")
				{:ok, req, state}
			end
			def terminate(_req, _state) do
				:ok = :pg2.leave(@pg2, self())
			end
		end

		defmodule this_webserver do
			use Silverb
			require Logger
			require Pmaker
			def start do
				dispatch = :cowboy_router.compile([
					{:_, [
						{"/bullet", :bullet_handler, [{:handler, unquote(this_webhandler)}]},
						{"/index.html", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/[...]", unquote(this_resourceloader), [nil]}
					]}])
				res = {:ok, _} = Pmaker.start_server(unquote(fullconf), unquote(String.to_atom(module)), unquote(port), dispatch)
				_ = Logger.info("HTTP(S) BULLET server started at port #{ unquote(port) }")
				res
			end
		end

	# BULLET #
	##########

	##########
	# COWBOY #

	(fullconf = %{ module: module, app: main_app, port: port, kind: :cowboy, decode: decode, encode: encode, crossdomain: crossdomain, callback_module: callback_module, priv_path: priv_path }) ->

		this_webhandler = String.to_atom("Elixir.Pmaker.Servers.#{module}.Handler")
		this_crossdomain = String.to_atom("Elixir.Pmaker.Servers.#{module}.Crossdomain")
		this_resourceloader = String.to_atom("Elixir.Pmaker.Servers.#{module}.ResourceLoader")
		this_webserver = String.to_atom("Elixir.Pmaker.Servers.#{module}.WebServer")

		defmodule this_crossdomain do
			use Silverb, [
				{"@crossdomainxml",
					"""
					<?xml version="1.0"?>
					<!-- http://www.adobe.com/crossdomain.xml -->
					<cross-domain-policy>
					<allow-access-from domain="*" secure="false" to-ports="*"/>
					</cross-domain-policy>
					"""}
			]
			def terminate(_reason, _req, _state), do: :ok
			def init(_, req, _opts), do: init_proc(req)
			def handle(req, :reply), do: {:ok, req, nil}
			def handle(req, _state), do: init_proc(req)
			case crossdomain do
				true ->
					defp init_proc(req) do
						case Pmaker.auth?(req) do
							{true, req} ->
								{:ok, req} = :cowboy_req.reply(200, [{"Content-Type","text/xml; charset=utf-8"},{"Access-Control-Allow-Origin", "*"},{"Connection","Keep-Alive"}], @crossdomainxml, req)
								{:ok, req, :reply}
							response -> response
						end
					end
				false ->
					defp init_proc(req) do
						{:ok, req} = :cowboy_req.reply(404, [{"Content-Type","text/xml; charset=utf-8"},{"Connection","Keep-Alive"}], "File not found. Note, crossdomain is not allowed.", req)
						{:ok, req, :reply}
					end
			end
		end

		defmodule this_resourceloader do
			require Pmaker
			Pmaker.resource_loader([main_app: unquote(main_app), priv_path: unquote(priv_path)])
		end

		defmodule this_webhandler do
			use Silverb
			require Logger
			require Pmaker
			@callback_module callback_module
			@response_headers (case crossdomain do ; true -> [{"Connection","Keep-Alive"},{"Access-Control-Allow-Origin", "*"}] ; false -> [{"Connection","Keep-Alive"}] ; end)

			Pmaker.decode_macro([decode: decode])
			Pmaker.encode_macro([encode: encode])

			case crossdomain do
				true ->
					defp handle_options(req) do
						{headers, req} = :cowboy_req.headers(req)
						headers = Enum.map(headers, fn({k,v}) ->
							case String.downcase(k) |> String.strip do
								"access-control-request-method" -> {"access-control-allow-method",v}
								"access-control-request-headers" -> {"access-control-allow-headers",v}
								_ -> {k,v}
							end
						end)
						{:ok, req} = :cowboy_req.reply(200, ([{"Access-Control-Allow-Origin", "*"},{"Connection","Keep-Alive"}]++headers), "", req)
						{:ok, req, :reply}
					end
				false ->
					defp handle_options(req) do
						{:ok, req} = :cowboy_req.reply(404, @response_headers, "", req)
						{:ok, req, :reply}
					end
			end

			def terminate(_,_,_), do: :ok
			def init(_,req,_), do: init_func(req)
			def handle(req, :reply), do: {:ok, req, nil}
			def handle(req, _), do: init_func(req)
			defp init_func(req) do
				case Pmaker.auth?(req) do
					{true, req} ->
						case :cowboy_req.method(req) do
							{"OPTIONS", req} -> handle_options(req)
							_ ->
								{qs,req} = :cowboy_req.qs_vals(req)
								qs_data = Enum.reduce(qs, %{}, fn({k,v},acc) -> Map.put(acc, Maybe.to_atom(k), Maybe.to_integer(v)) end)
								case :cowboy_req.has_body(req) do
									# GET
									false -> %Pmaker.Request{qs: qs_data}
									# GET + POST
									true ->
										{:ok, req_body, _} = :cowboy_req.body(req)
										decode(req_body)
										|> Map.update!(:qs, fn(qs = %{}) -> Map.merge(qs_data, qs) end)
								end
								|> @callback_module.handle_pmaker
								|> finalyze_request(req)
						end
					response -> response
				end
			end
			defp finalyze_request(%Pmaker.Response{data: reply_data, encode: encode, status: status}, req) do
				{:ok, req} = :cowboy_req.reply(status, @response_headers, (case encode do ; true -> encode(reply_data) ; false -> reply_data ; end), req)
				{:ok, req, :reply}
			end

		end

		defmodule this_webserver do
			use Silverb
			require Logger
			require Pmaker
			def start do
				dispatch = :cowboy_router.compile([
					{:_, [
						{"/cowboy", unquote(this_webhandler), []},
						{"/crossdomain.xml", unquote(this_crossdomain), []},
						{"/index.html", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/", unquote(this_resourceloader), ["#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}/index.html"]},
						{"/[...]", unquote(this_resourceloader), [nil]}
					]}])
				res = {:ok, _} = Pmaker.start_server(unquote(fullconf), unquote(String.to_atom(module)), unquote(port), dispatch)
				_ = Logger.info("HTTP(S) COWBOY server started at port #{ unquote(port) }")
				res
			end
		end

	# COWBOY #
	##########

end)
