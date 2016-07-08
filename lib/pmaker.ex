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

	defmacro resource_loader([main_app: main_app]) do
		authfunc = case Application.get_env(:pmaker, :basic_auth) do
			nil ->
				quote location: :keep do
					defp auth?(req) do
						{true, req}
					end
				end
			%{login: login, password: password} ->
				quote location: :keep do
					defp auth?(req) do
						case {:cowboy_req.parse_header("authorization", req), unquote(login), unquote(password)} do
							{{:ok, {"basic",{login,password}}, req}, login, password} -> {true, req}
							_ -> {false, req}
						end
					end
				end
		end
		quote location: :keep do
			use Silverb
			require Record
			Record.defrecord :http_req, [socket: :undefined, transport: :undefined, connection: :keepalive, pid: :undefined, method: "GET", version: :"HTTP/1.1", peer: :undefined, host: :undefined, host_info: :undefined, port: :undefined, path: :undefined, path_info: :undefined, qs: :undefined, qs_vals: :undefined, bindings: :undefined, headers: [], p_headers: [], cookies: :undefined, meta: [], body_state: :waiting, multipart: :undefined, buffer: "", resp_compress: false, resp_state: :waiting, resp_headers: [], resp_body: "", onresponse: :undefined]
			def init(_, req, [path]) when is_binary(path) do
				case auth?(req) do
					{true, req} -> {:ok, :cowboy_req.reply(200, [{"Content-Type","text/html; charset=utf-8"},{"connection","close"}], File.read!(path), req) |> elem(1), nil}
					{false, req} -> {:ok, :cowboy_req.reply(401, [{"WWW-Authenticate", "Basic realm=\"authentication required\""},{"connection","close"}], "", req) |> elem(1), nil}
				end
			end
			def init(_, req = http_req(path: path), [nil]) when is_binary(path) do
				case auth?(req) do
					{true, req} ->
						filename = "#{ unquote(main_app) |> :code.priv_dir |> :erlang.list_to_binary }#{path}"
						case File.exists?(filename) do
							true -> {:ok, :cowboy_req.reply(200, [{"Content-Type",:mimetypes.filename(path) |> List.first},{"connection","close"}], File.read!(filename), req) |> elem(1), nil}
							false -> {:ok, :cowboy_req.reply(404, [{"connection","close"}], "", req) |> elem(1), nil}
						end
					{false, req} -> {:ok, :cowboy_req.reply(401, [{"WWW-Authenticate", "Basic realm=\"authentication required\""},{"connection","close"}], "", req) |> elem(1), nil}
				end
			end
			def init(_, req, _), do: {:ok, :cowboy_req.reply(404, [{"connection","close"}], "", req) |> elem(1), nil}
			def handle(req, _), do: {:ok, req, nil}
			def terminate(_,_,_), do: :ok
			unquote(authfunc)
		end
	end

end
