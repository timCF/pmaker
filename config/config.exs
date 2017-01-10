# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :pmaker, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:pmaker, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"

config :logger, level: :debug
config :pmaker,
	basic_auth: %{login: "login", password: "password"}, # if needed
	# can run multiple servers on one OTP app
	servers: [
		%{
			module: "BulletServer1", # just server name
			app: :pmaker, # main app ( for loading resources etc )
			port: 7770, # webserver port
			kind: :bullet, # :bullet | :cowboy
			decode: nil, # nil | :json | :callback
			encode: nil, # nil | :json | :callback
			crossdomain: true, # true | false
			callback_module: Pmaker.Example.Bullet, # where are callbacks functions :
			# mandatory &handle_pmaker/1 gets %Pmaker.Request{}, returns %Pmaker.Response{}
			# optional &decode/1 returns {:ok, term} | {:error, error}
			# optional &encode/1
			priv_path: "/html_app1", # path in priv dir for resource loader
			# ssl disabled
			cacertfile: false,
			certfile: false,
			keyfile: false,
		},
		%{
			module: "BulletServer2", # just server name
			app: :pmaker, # main app ( for loading resources etc )
			port: 7771, # webserver port
			kind: :bullet, # :bullet | :cowboy
			decode: nil, # nil | :json | :callback
			encode: nil, # nil | :json | :callback
			crossdomain: true, # true | false
			callback_module: Pmaker.Example.Bullet, # where are callbacks functions :
			# mandatory &handle_pmaker/1 gets %Pmaker.Request{}, returns %Pmaker.Response{}
			# optional &decode/1 returns {:ok, term} | {:error, error}
			# optional &encode/1
			priv_path: "/html_app2", # path in priv dir for resource loader
			# ssl settings
			cacertfile: "/ssl/cowboy-ca.crt",
			certfile: "/ssl/server.crt",
			keyfile: "/ssl/server.key",
		},
		%{
			module: "CowboyServer1", # just server name
			app: :pmaker, # main app ( for loading resources etc )
			port: 7772, # webserver port
			kind: :cowboy, # :bullet | :cowboy
			decode: :callback, # nil | :json | :callback
			encode: :callback, # nil | :json | :callback
			crossdomain: true, # true | false
			callback_module: Pmaker.Example.Cowboy, # where are callbacks functions :
			# mandatory &handle_pmaker/1 gets %Pmaker.Request{}, returns %Pmaker.Response{}
			# optional &decode/1 returns {:ok, term} | {:error, error}
			# optional &encode/1
			priv_path: "/html_app3", # path in priv dir for resource loader
			# ssl settings
			cacertfile: "/ssl/cowboy-ca.crt",
			certfile: "/ssl/server.crt",
			keyfile: "/ssl/server.key",
		}
	]
