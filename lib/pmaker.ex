defmodule Pmaker.Request do
	defstruct [
		qs: %{},
		data: "",
		ok: true,
		error: ""
	]
end
defmodule Pmaker.Response do
	defstruct [
		status: 200,
		data: "",
		encode: true # do or not encode before send
	]
end
defmodule Pmaker do
	use Application
	use Silverb, [
		{"@basic_auth", (case Application.get_env(:pmaker, :basic_auth) do ; nil -> nil ; data = %{login: login, password: password} when (is_binary(login) and is_binary(password)) -> data ; end)},
		{"@servers", Application.get_env(:pmaker, :servers)}
	]
	# See http://elixir-lang.org/docs/stable/elixir/Application.html
	# for more information on OTP Applications
	def start(_type, _args) do
		import Supervisor.Spec, warn: false
		:ok = Application.put_env(:bullet, :basic_auth, @basic_auth)
		:ok = Enum.each(@servers, fn(data = %{kind: kind, module: module}) ->
			if (kind == :bullet), do: (:ok = data |> get_pg2 |> :pg2.create)
			_ = String.to_atom("Elixir.Pmaker.Servers.#{module}.WebServer").start()
		end)

		# Define workers and child supervisors to be supervised
		children = [
		# Starts a worker by calling: Pmaker.Worker.start_link(arg1, arg2, arg3)
		# worker(Pmaker.Worker, [arg1, arg2, arg3]),
		]

		# See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
		# for other strategies and supported options
		opts = [strategy: :one_for_one, name: Pmaker.Supervisor]
		Supervisor.start_link(children, opts)
	end
	def stop(_), do: :erlang.halt

	def get_pg2(%{module: module}), do: "__pmaker__pg2__#{module}__"

	def send2all(res = %Pmaker.Response{}, module) do
		get_pg2(%{module: module})
		|> :pg2.get_members
		|> Enum.each(&(send(&1, res)))
	end

	# func for cowboy req
	case Application.get_env(:pmaker, :basic_auth) do
		nil ->
			def auth?(req) do
				{true, req}
			end
		%{login: login, password: password} ->
			def auth?(req) do
				case {:cowboy_req.parse_header("authorization", req), unquote(login), unquote(password)} do
					{{:ok, {"basic",{login,password}}, req}, login, password} -> {true, req}
					_ -> {:ok, :cowboy_req.reply(401, [{"WWW-Authenticate", "Basic realm=\"authentication required\""},{"connection","close"}], "", req) |> elem(1), :reply}
				end
			end
	end

	defmacro decode_macro([decode: decode]) do
		quote location: :keep do
			case unquote(decode) do
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
		end
	end

	defmacro encode_macro([encode: encode]) do
		quote location: :keep do
			case unquote(encode) do
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
		end
	end

	defmacro start_server(%{cacertfile: cacertfile, certfile: certfile, keyfile: keyfile}, module, port, dispatch) when (is_binary(cacertfile) and is_binary(certfile) and is_binary(keyfile)) do
		quote location: :keep do
			:cowboy.start_https(unquote(module), 5000, [port: unquote(port), cacertfile: unquote(cacertfile), certfile: unquote(certfile), keyfile: unquote(keyfile)], [env: [ dispatch: unquote(dispatch) ] ])
		end
	end
	defmacro start_server(%{}, module, port, dispatch) do
		quote location: :keep do
			:cowboy.start_http(unquote(module), 5000, [port: unquote(port)], [env: [ dispatch: unquote(dispatch) ] ])
		end
	end

	defmacro resource_loader([main_app: main_app, priv_path: priv_path]) do
		quote location: :keep do
			use Silverb
			require Record
			Record.defrecord :http_req, [socket: :undefined, transport: :undefined, connection: :keepalive, pid: :undefined, method: "GET", version: :"HTTP/1.1", peer: :undefined, host: :undefined, host_info: :undefined, port: :undefined, path: :undefined, path_info: :undefined, qs: :undefined, qs_vals: :undefined, bindings: :undefined, headers: [], p_headers: [], cookies: :undefined, meta: [], body_state: :waiting, multipart: :undefined, buffer: "", resp_compress: false, resp_state: :waiting, resp_headers: [], resp_body: "", onresponse: :undefined]
			def init(_, req, [path]) when is_binary(path) do
				case Pmaker.auth?(req) do
					{true, req} -> {:ok, :cowboy_req.reply(200, [{"Content-Type","text/html; charset=utf-8"},{"connection","close"}], File.read!(path), req) |> elem(1), nil}
					response -> response
				end
			end
			def init(_, req = http_req(path: path), [nil]) when is_binary(path) do
				case Pmaker.auth?(req) do
					{true, req} ->
						filename = "#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{unquote(priv_path)}#{path}"
						case File.exists?(filename) do
							true -> {:ok, :cowboy_req.reply(200, [{"Content-Type",:mimetypes.filename(path) |> List.first},{"connection","close"}], File.read!(filename), req) |> elem(1), nil}
							false -> {:ok, :cowboy_req.reply(404, [{"connection","close"}], "", req) |> elem(1), nil}
						end
					response -> response
				end
			end
			def init(_, req, _), do: {:ok, :cowboy_req.reply(404, [{"connection","close"}], "", req) |> elem(1), nil}
			def handle(req, _), do: {:ok, req, nil}
			def terminate(_,_,_), do: :ok
		end
	end

end
