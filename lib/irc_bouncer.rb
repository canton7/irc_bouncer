require 'data_mapper'
require 'dm-sqlite-adapter'
require 'dm-validations'
require 'eventmachine'

require_relative 'irc_bouncer/models/user'
require_relative 'irc_bouncer/models/server'
require_relative 'irc_bouncer/models/channel'
require_relative 'irc_bouncer/models/server_conn'
require_relative 'irc_bouncer/models/message_log'
require_relative 'irc_bouncer/models/join_command'

require_relative 'irc_bouncer/irc_server'
require_relative 'irc_bouncer/irc_client'
require_relative 'irc_bouncer/ini_parser'
require_relative 'irc_bouncer/version'

module IRCBouncer
	CONFIG_DEFAULTS = {
		'server.address' => ['0.0.0.0', 'Address to bind to'],
		'server.port' => [1234, 'Port to bind to'],
		'server.verbose' => [false, 'Print out all traffic'],
		'user.can_create_servers' => [false, 'Allow users to connect to servers other than those spicified by the admins'],
	}

	@@server_connections = {}
	@@client_connections = {}
	@@exec_dir = File.expand_path(
		File.exists?(File.join(File.dirname(__FILE__), '..',  'debug_mode')) ? 
			File.join(File.dirname(__FILE__), '..') : 
			File.join(Dir.home, '.irc_bouncer')
	)
	@@config

	def self.initial_setup
		return if Dir.exists?(@@exec_dir)
		Dir.mkdir(@@exec_dir)
	end
	
	def self.load_config
		@@config = IniParser.new(File.join(@@exec_dir, 'config.ini'), CONFIG_DEFAULTS).load
	end

	def self.setup_db
		DataMapper::Logger.new($stdout, :warn)
		DataMapper::setup(:default, "sqlite:///#{@@exec_dir}/db.sqlite")
		DataMapper.finalize
		DataMapper.auto_upgrade!
	end
	
	def self.run!
		initial_setup
		load_config
		setup_db

		connections = []
		
		begin
			EventMachine::run do
				IRCServer.new(@@config['server.address'], @@config['server.port']).run!
				User.all.each do |user|
					user.server_conns.each do |server_conn|
						server = server_conn.server
						connection = IRCClient.new(server_conn, user).run!
						@@server_connections[[server.name, user.name]] = connection
					end
				end
			end
		rescue RuntimeError => e
			puts "Failed to start server: #{e.message}"
			puts "Retrying in 10 seconds"
			sleep(10)
			retry
		end
	end
	
	# Called when a new client connects to our IRC server
	def self.connect_client(client_connection, server_conn, user)
		server = server_conn.server
		return false if @@client_connections.has_key?([server.name, user.name])
		connection = @@server_connections[[server.name, user.name]]
		# If the connection to that server doesn't already exist for this user, make it
		@@server_connections[[server.name, user.name]] = IRCClient.new(server_conn, user).run! unless connection
		# This has to go about the @@server_connections line, as IRCClient uses the presence of the element in
		# @@client_connections to determine whether to send USER information
		@@client_connections[[server.name, user.name]] = client_connection
		return connection
	end

	def self.data_from_client(server, name, data)
		conn = @@server_connections[[server, name]]
		conn.send(data) if conn
	end

	def self.data_from_server(server, name, data)
		conn = @@client_connections[[server, name]]
		conn.send(data) if conn
	end

	def self.client_died(server, name)
		@@client_connections.delete([server, name])
	end

	def self.server_died(server, name)
		@@server_connections.delete([server, name])
	end
	
	def self.client_connected?(server, name)
		@@client_connections.has_key?([server, name])
	end
	
	def self.server_send_messages(server, name)
		conn = @@client_connections[[server, name]]
		conn.send_message_log if conn
	end
	
	def self.server_registered?(server, name)
		@@server_connections[[server, name]].registered?
	end
	
	def self.config
		@@config
	end
	
end

IRCBouncer.run!
