module IRCBouncer
	class IRCClient
		attr_reader :server_name, :nick
		@server
		@port
		@join_cmds
		
		def initialize(server_name, server, port, nick, join_cmds)
			@server_name, @server, @port, @nick, @join_cmds = server_name, server, port, nick, join_cmds
		end
		
		def run!
			EventMachine::connect(@server, @port, Handler) do |c|
				c.init(@server_name, @nick)
				return c
			end
		end
		
		class Handler < EventMachine::Connection
			include EventMachine::Protocols::LineText2
			
			# Name of the server we're the connection to, and
			# nick of the person we're the connection for
			@server
			@nick
			
			def initialize(*args)
				super
				puts "IRC Client is Connected"
			end
			
			def init(server, nick)
				@server, @nick = server, nick
			end
			
			def receive_line(data)
				puts "<-- (Client) #{data}"
				relay(data)
			end
			
			def unbind
				puts "IRC Client is Disconnected"
				IRCBouncer.server_died(@server, @nick)
			end
			
			def send(data)
				puts "--> (Client) #{data}"
				send_data(data << "\n")
			end

			def join_server(user, server_conn)
				return if server_conn.connected
				send("USER #{user.name} \"#{server_conn.host}\" \"#{server_conn.servername}\" :#{server_conn.name}")
				send("NICK #{server_conn.nick}")
				server_conn.update(:connected => true)
				server_conn.channels.each do |channel|
					send("join #{channel.name}")
				end
			end

			def join_channel(channel)
				send("join ##{channel}")
			end
			
			def relay(data)
				IRCBouncer.data_from_server(@server, @nick, data)
			end
		end
	end
end