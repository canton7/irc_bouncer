module IRCBouncer
	class IRCServer
		@server
		@port
		
		def initialize(server, port)
				@server, @port = server, port
		end
		
		def run!
			EventMachine::start_server(@server, @port, Handler)
			#EventMachine::add_periodic_timer(1){ send_data "PING" }
			puts "Server started "
		end
		
		class Handler < EventMachine::Connection
			include EventMachine::Protocols::LineText2
			
			@ping_state
			@server
			@server_conn
			@user
			@nick # Only used between NICK and USER commands
			
			def initialize(*args)
				super
				puts "IRC Server New Connection"
				EventMachine::PeriodicTimer.new(120){ ping }
				@ping_state = :received
			end
			
			# Callbacks

			def receive_line(data)
				handle(data.chomp)
			end

			def unbind
				puts "IRC Server Connection Died"
				IRCBouncer.client_died(@server.name, @user.name)
			end

			# Methods

			def handle(data)
				puts "<-- (Server) #{data}"
				case data
				when /^NICK (?<nick>.+?)$/
					@nick = $~[:nick]
				when /^USER (?<user>.+?)\s"(?<host>.+?)"\s"(?<server>.+?)"\s:(?<name>.+?)$/
					identify_user($~)
				when /^join #(?<room>.+)$/
					join_channel($~[:room])
				when /^PONG :(?<server>.+)$/
					@ping_state = :received
				else
					relay(data)
				end
			end

			def identify_user(parts)
				conn_user, server_name = parts[:user].split('@')
				# TODO proper exception handling
				unless server_name
					puts "Invalid name (no server)"
					close_connection
				end
				@server = Server.first(:name => server_name)
				@user = User.first(:name => conn_user)
				@server_conn = @user.server_conns.first_or_create(:server => @server)
				@server_conn.update(:host => parts[:host], :servername => parts[:server], :name => parts[:name], :nick => @nick)
				# The actual connection goes through IRCClient for cleaness
				IRCBouncer.connect_client(self, @server_conn, @user)
				# Send them the message backlog
				JoinLog.all(:server_conn => @server_conn).each{ |m| send(m.message) }
				# Ask for the topics of all joined rooms
				@server_conn.channels.each{ |c| relay("TOPIC #{c.name}") }
				# Ask for the names of joined channels
				channels = @server_conn.channels.map{ |c| c.name }.join(', ')
				relay("NAMES #{channels}")
			end

			def join_channel(channel_name)
				channel = @server_conn.channels.first(:name => "##{channel_name}")
				puts "Looking for channel #{channel_name}..."
				unless channel
					new_channel = Channel.first_or_create(:name => "##{channel_name}", :server => @server)
					@server_conn.channels << new_channel
					@server_conn.save
				end
				relay("join ##{channel_name}")
			end

			def send(data)
				puts "--> (Server) #{data}"
				send_data(data << "\n")
			end
			
			def relay(data)
				IRCBouncer.data_from_client(@server.name, @user.name, data) if @server && @user
			end
			
			def ping
				puts "NO RESPONSE" unless @ping_state == :received
				send("PING :irc.antonymale.co.uk")
				@ping_state = :sent
			end
		end
	end
end