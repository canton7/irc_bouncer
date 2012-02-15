require 'data_mapper'
require 'dm-sqlite-adapter'
require 'eventmachine'

require_relative 'irc_bouncer/models/user'
require_relative 'irc_bouncer/models/server'
require_relative 'irc_bouncer/models/channel'
require_relative 'irc_bouncer/models/join_command'
require_relative 'irc_bouncer/models/server_conn'

require_relative 'irc_bouncer/irc_server'
require_relative 'irc_bouncer/irc_client'

module IRCBouncer
	@@server_connections = {}
	@@client_connections = {}

	def self.setup_db
		DataMapper::Logger.new($stdout, :warn)
		DataMapper::setup(:default, "sqlite:///#{Dir.pwd}/db.sqlite")
		DataMapper.finalize
		DataMapper.auto_upgrade!
	end
	
	def self.run!
		setup_db

		connections = []

		ServerConn.update(:connected => false)

		
		EventMachine::run do
			IRCServer.new('localhost', 1234).run!
			User.all.each do |user|
				user.server_conns.each do |server_conn|
					server = server_conn.server
					connection = IRCClient.new(server.name, server.address, server.port, user.name, '').run!
					@@server_connections[[server.name, user.name]] = connection
					connection.join_server(user, server_conn)
				end
				#user.channels.each do |channel|
				#	@@server_connections[[channel.server.name, user.name]].join_channel(channel.name)
				#end
			end
		end
	end
	
	# Called when a new client connects to our IRC server
	def self.connect_client(client_connection, server, name)
		@@client_connections[[server, name]] = client_connection
		connection = @@server_connections[[server, name]]
		# If the connection to that server doesn't already exist for this user, make it
		unless connection
			server = Server.first(:name => server)
			user = User.first(:name => name)
			connection = IRCClient.new(server.name, server.address, server.port, name, '')
			@@server_connections[[server.name, name]] = connection.run!
		end
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

	def self.client_connect_to_server(server_name, user, server_conn)
		@@server_connections[[server_name, user.name]].join_server(user, server_conn)
	end

	def self.client_died(server, name)
		@@client_connections.delete([server, name])
	end

	def self.server_died(server, name)
		@@server_connections.delete([server, name])
	end
	
end

IRCBouncer.run! if $0 == __FILE__