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

module IRCBouncer
	@@server_connections = {}
	@@client_connections = {}
	@@exec_dir = File.join(Dir.home, '.irc_bouncer')

	def self.initial_setup
		return if Dir.exists?(@@exec_dir)
		Dir.mkdir(@@exec_dir)
	end

	def self.setup_db
		DataMapper::Logger.new($stdout, :warn)
		DataMapper::setup(:default, "sqlite:///#{@@exec_dir}/db.sqlite")
		DataMapper.finalize
		DataMapper.auto_upgrade!
	end
	
	def self.run!
		initial_setup
		setup_db

		connections = []

		EventMachine::run do
			IRCServer.new('localhost', 1234).run!
			User.all.each do |user|
				user.server_conns.each do |server_conn|
					server = server_conn.server
					connection = IRCClient.new(server_conn, user).run!
					@@server_connections[[server.name, user.name]] = connection
				end
			end
		end
	end
	
	# Called when a new client connects to our IRC server
	def self.connect_client(client_connection, server_conn, user)
		server = server_conn.server
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
		if conn
			conn.send(data)
		else
			puts "NEED TO LOG (from client) #{data}"
		end
	end

	def self.data_from_server(server, name, data)
		conn = @@client_connections[[server, name]]
		if conn
			conn.send(data)
		else
			puts "NEED TO LOG (from server) #{data}"
		end
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
	
end

IRCBouncer.run!
