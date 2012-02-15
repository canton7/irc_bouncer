require 'data_mapper'
require 'dm-sqlite-adapter'
require 'eventmachine'

require_relative 'irc_bouncer/models/user'
require_relative 'irc_bouncer/models/server'
require_relative 'irc_bouncer/models/channel'

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
		User.all.each do |user|
			user.servers.each do |server|
				connections << IRCClient.new(server.name, server.address, server.port, user.nick, '')
			end
		end
		
		EventMachine::run do
			IRCServer.new('localhost', 1234).run!
			connections.each do |c|
				@@server_connections[[c.server_name, c.nick]] = c.run!
			end
		end
	end
	
	# Called when a new client connects to our IRC server
	def self.connect_client(client_connection, server, nick)
		@@client_connections[[server, nick]] = client_connection
		connection = @@server_connections[[server, nick]]
		# If the connection to that server doesn't already exist for this user, make it
		unless connection
			server = Server.first(:name => server)
			user = User.first(:nick => nick)
			connection = IRCClient.new(server.name, server.address, server.port, user.nick, '')
			@@server_connections[[server.name, nick]] = connection.run!
		end
		return connection
	end
	
	def self.data_from_client(server, nick, data)
		#puts "DATA FROM [#{server}, #{nick}]: #{data}"
		@@server_connections[[server, nick]].send(data)
	end
	
	def self.data_from_server(server, nick, data)
		@@client_connections[[server, nick]].send(data)
	end
	
end

IRCBouncer.run! if $0 == __FILE__