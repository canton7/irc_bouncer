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
			@conn_parts # Used when they sent USER w/o '@server', and we need to save
			
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
				when /^NICK\s(?<nick>.+?)$/i
					change_nick($~[:nick], data)
				when /^USER\s(?<user>.+?)\s"(?<host>.+?)"\s"(?<server>.+?)"\s:(?<name>.+?)$/
					identify_user($~)
				when /^JOIN\s#(?<room>.+)$/i
					join_channel($~[:room])
				when /^PONG\s:(?<server>.+)$/
					@ping_state = :received
				when /^RELAY\s(?<args>.+)$/i
					relay_cmd($~[:args])
				else
					relay(data)
				end
			end

			def identify_user(parts)
				@conn_parts = parts
				conn_user, server_name = parts[:user].split('@')
				@user = User.first(:name => conn_user)
				if server_name
					create_server_conn(server_name)
				else server_name
					msg_client("You haven't included a server in your name")
					msg_client("To automatically connect to a server, set your name to #{conn_user}@<server>")
					return
				end
			end
			
			def create_server_conn(server_name)
				if @server && @server.name == server_name
					msg_client("Already connected to #{server_name}")
					return
				end
				msg_client("Connecting to #{server_name}...")
				@server = Server.first(:name => server_name)
				unless @server
					msg_client("The server '#{server_name}' doesn't exist")
					list_servers
					return
				end
				@server_conn = @user.server_conns.first_or_create(:server => @server)
				@server_conn.update(:host => @conn_parts[:host], :servername => @conn_parts[:server],
					:name => @conn_parts[:name], :nick => @nick)
				# The actual connection goes through IRCClient for cleaness
				IRCBouncer.connect_client(self, @server_conn, @user)
				rejoin_client
			end
			
			def rejoin_client
				# Only if we've registered... Client can connect v. early on in reg process
				# and server complains that we're not yet registered when we send NAMES/TOPIC
				if IRCBouncer.server_registered?(@server.name, @user.name)
					# MOTD...
					relay("MOTD")
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
			
			def quit_server(server_name)
				relay("QUIT")
				server = (server_name) ? Server.first(:name => server_name) : @server
				unless server
					msg_client("Server #{server_name} not found")
					return
				end
				@user.server_conns.all(:server => server).destroy!
				msg_client("You have been disconnected from #{server.name}")
				close_client if server == @server
			end
			
			def msg_client(message)
				send(":IRCRelay!IRCRelay@ircrelay. NOTICE #{@nick} :#{message}")
			end
			
			def list_servers
				msg_client("Available servers are:")
				Server.all.each do |server|
					msg = " - #{server.name}   #{server.address}:#{server.port}"
					if @user && @user.server_conns.count(:server => server) > 0
						msg << "  (connected" 
						msg << (@server == server ? ", current)" : ")")
					end
					msg_client(msg)
				end
			end
			
			def create_server(parts)
				server = Server.new(:name => parts[:name], :address => parts[:address], :port => parts[:port])
				if server.save
					msg_client("Server #{parts[:name]} created")
				else
					msg_client("Failed: #{server.errors.to_a.join(', ')}")
				end
			end
			
			def delete_server(name)
				server = Server.first(:name => name)
				unless server
					msg_client("Can't find server #{name}")
					return
				end
				unless ServerConn.all(:server => server).empty?
					msg_client("People are currently connected to #{name}")
					return
				end
				server.channels.all.destroy!
				server.destroy!
				msg_client("Deleted #{name}")
			end
			
			def create_user(name, pass, is_admin)
				user = User.new(:name => name, :server_pass => pass, :level => (is_admin ? :admin : :user))
				if user.save
					msg_client("#{is_admin ? "Admin" : "User"} #{name} created")
				else
					msg_client("Failed: #{user.errors.to_a.join(', ')}")
				end
			end
			
			def delete_user(name)
				user = User.first(:name => name)
				unless user
					msg_client("User #{name} doesn't exist")
					return
				end
				if user == @user
					msg_client("You can't delete yourself!")
					return
				end
				if user.server_conns.any?{ |conn| IRCBouncer.client_connected?(conn.server.name, user.name) }
					msg_client("That user is connected to a server")
					return
				end
				user.server_conns.all.destroy!
				user.destroy!
				msg_client("User #{name} deleted")
			end
			
			def relay_cmd(cmd)
				case cmd
				when /^LIST$/i
					list_servers
				when /^CONNECT\s(?<server>.+)$/i
					create_server_conn($~[:server])
				when /^QUIT(?:\s(?<server>.+))?$/i
					quit_server($~[:server])
				when /^CREATE\s(?<name>.+?)\s(?<address>.+?):(?<port>\d+)$/i
					create_server($~) if check_is_admin
				when /^DELETE\s(?<name>.+)$/i
					delete_server($~[:name]) if check_is_admin
				when /^CREATE_(?<type>USER|ADMIN)\s(?<name>.+?)\s(?<pass>.+)$/i
					create_user($~[:name], $~[:pass], $~[:type].downcase == 'admin') if check_is_admin
				when /^DELETE_USER\s(?<name>.+)$/i
					delete_user($~[:name]) if check_is_admin
				else
					msg_client("Command #{cmd} not recognised")
				end
			end
			
			def check_is_admin
				return true if @user.level == :admin
				msg_client("You need to be an admin to do that")
				return false
			end

			def send(data)
				puts "--> (Server) #{data}"
				send_data(data << "\n")
			end
			
			def relay(data)
				IRCBouncer.data_from_client(@server.name, @user.name, data) if @server && @user
			end
			
			def close_client(msg=nil)
				msg_client(msg) if msg
				msg_client("Disconnecting...")
				close_connection_after_writing
			end
			
			def ping
				puts "NO RESPONSE" unless @ping_state == :received
				send("PING :irc.antonymale.co.uk")
				@ping_state = :sent
			end
		end
	end
end