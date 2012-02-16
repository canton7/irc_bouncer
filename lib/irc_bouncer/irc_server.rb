module IRCBouncer
	class IRCServer
		DOW = %W{Sun Mon Tue Wed Thu Fri Sat}
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
			@conn_user # Used when they sent USER w/o '@server', and we need to save
			
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
				IRCBouncer.client_died(@server.name, @user.name) if @server && @user
			end

			# Methods

			def handle(data)
				puts "<-- (Server) #{data}"
				case data
				when /^NICK (?<nick>.+?)$/i
					change_nick($~[:nick], data)
				when /^USER (?<user>.+?)\s"(?<host>.+?)"\s"(?<server>.+?)"\s:(?<name>.+?)$/
					identify_user($~)
				when /^JOIN #(?<room>.+)$/i
					join_channel($~[:room])
				when /^PONG :(?<server>.+)$/
					@ping_state = :received
				else
					relay(data)
				end
			end

			def identify_user(parts)
				conn_user, server_name = parts[:user].split('@')
				@user = User.first(:name => conn_user)
				if server_name
					create_server_conn(server_name, parts)
				else server_name
					@conn_user = parts
					msg_client("You haven't included a server in your name")
					msg_client("To automatically connect to a server, set your name to #{conn_user}@<server>")
					return
				end
			end
			
			def create_server_conn(server_name, parts)
				@server = Server.first(:name => server_name)
				unless @server
					msg_client("The server '#{server_name}' doesn't exist")
					list_servers
					return
				end
				@server_conn = @user.server_conns.first_or_create(:server => @server)
				@server_conn.update(:host => parts[:host], :servername => parts[:server], :name => parts[:name], :nick => @nick)
				# The actual connection goes through IRCClient for cleaness
				IRCBouncer.connect_client(self, @server_conn, @user)
				rejoin_client
			end
			
			def rejoin_client
				# Send them the message backlog
				JoinLog.all(:server_conn => @server_conn).each{ |m| send(m.message) }
				# Only if we've registered... Client can connect v. early on in reg process
				# and server complains that we're not yet registered when we send NAMES/TOPIC
				if IRCBouncer.server_registered?(@server.name, @user.name)
					# Ask for the topics of all joined rooms
					@server_conn.channels.each{ |c| relay("TOPIC #{c.name}") }
					# Ask for the names of joined channels
					channels = @server_conn.channels.map{ |c| c.name }.join(', ')
					relay("NAMES #{channels}")
				end
				# Play back messages
				messages = MessageLog.all(:server_conn => @server_conn)
				messages.each do |m|
					time = m.timestamp.strftime("%H:%M")
					time = "#{DOW[m.timestamp.wday]} #{time}" if Time.now - m.timestamp > 60*60*24
					send(":#{m.header} :[#{time}] #{m.message}")
				end
				msg_client("Wootsicles")
				messages.destroy!
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
			
			def change_nick(nick, data)
				@nick = nick
				if @server_conn
					@server_conn.update(:nick => @nick)
					relay(data)
				end
			end
			
			def msg_client(message)
				send(":IRCRelay!IRCRelay@ircrelay. NOTICE #{@nick} :#{message}")
			end
			
			def list_servers
				msg_client("Available servers are:")
				Server.all.each do |server|
					msg = " - #{server.name}   #{server.address}:#{server.port}"
					msg << "  (connected)" if @user && @user.server_conns.count(:server => server) > 0
					msg_client(msg)
				end
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