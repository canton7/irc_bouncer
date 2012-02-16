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
			puts "Server started"
		end
		
		class Handler < EventMachine::Connection
			include EventMachine::Protocols::LineText2
			
			@ping_count
			@server
			@server_conn
			@user
			@nick # Only used between NICK and USER commands
			@pass # Ditto
			@conn_parts # Used when they sent USER w/o '@server', and we need to save
			@verbose
			
			# Callbacks
			
			def post_init()
				port, ip = Socket.unpack_sockaddr_in(get_peername)
				log("Client Connected from #{ip}:#{port}")
				EventMachine::PeriodicTimer.new(120){ ping }
				@ping_count = 0
				@verbose = IRCBouncer.config['server.verbose']
				send("NOTICE * :Welcome to IRCRelay")
			end
			
			def receive_line(data)
				handle(data.chomp)
			end

			def unbind
				log("Client Disconnected")
				IRCBouncer.client_died(@server.name, @user.name) if @server && @user
			end

			# Methods

			def handle(data)
				log("<-- (Server) #{data}") if @verbose
				case data
				when /^NICK\s(?<nick>.+?)$/i
					change_nick($~[:nick], data)
				when /^PASS\s(?<pass>.+)$/
					@pass = $~[:pass]
				when /^USER\s(?<user>.+?)(?:@(?<server_name>.+?))?\s"?(?<host>.+?)"?\s"?(?<server>.+?)"?\s:(?<name>.+?)$/
					identify_user($~)
				when /^JOIN\s#(?<room>.+)$/i
					join_channel($~[:room])
				when /^PRIVMSG\snickserv\s:identify\s(?<pass>.+)$/i
					add_join_command(data)
				when /^PONG\s:(?<server>.+)$/
					@ping_count = 0
				when /^RELAY\s:?(?<args>.+)$/i
					relay_cmd($~[:args])
				when /^QUIT/i
					log("Client quit")
				else
					relay(data)
				end
			end

			def identify_user(parts)
				@conn_parts = parts
				@user = User.first(:name => parts[:user])
				no_users = User.all.empty?
				unless @pass
					msg_client("Please speficy a server password to connect")
					msg_client("This will become your password") if no_users
					close_client
					return
				end
				msg_client("*"*57)
				msg_client("* Welcome to IRCBouncer. Use /relay help to view commands *")
				msg_client("*"*57)
				if no_users
					msg_client("Since you're the first person to connect, I'm making you an admin")
					@user = create_user(parts[:user], @pass, true)
				end
				unless @user
					close_client("I don't know you #{parts[:user]}. Get an admin to create you")
					return
				end
				close_client("Incorrect password") && return unless @pass == @user.server_pass
				log("Client identified: #{parts[:user]}")
				if parts[:server_name]
					create_server_conn(parts[:server_name])
				else
					msg_client("You haven't included a server in your name")
					msg_client("To automatically connect to a server, set your name to #{parts[:user]}@<server_name>")
					msg_client("Type /relay list to view available servers")
					return
				end
			end
			
			def create_server_conn(server_name)
				if @server && @server.name == server_name
					msg_client("Already connected to #{server_name}")
					return
				end
				msg_client("Connecting to #{server_name}...")
				if IRCBouncer.client_connected?(server_name, @conn_parts[:user])
					msg_client("You are already connected to #{server_name}, probably from another connection")
					msg_client("This is not yet something which is supported")
					return
				end
				@server = Server.first(:name => server_name)
				unless @server
					msg_client("The server '#{server_name}' doesn't exist")
					list_servers
					return
				end
				@server_conn = @user.server_conns.first_or_create(:server => @server)
				@server_conn.update(:host => @conn_parts[:host], :servername => @conn_parts[:server],
					:name => @conn_parts[:user], :nick => @nick)
				# The actual connection goes through IRCClient for cleaness
				begin
					IRCBouncer.connect_client(self, @server_conn, @user)
					rejoin_client
				rescue EventMachine::ConnectionError => e
					msg_client("Failed to connect to server #{@server.name}: #{e.message}")
					@server = @server_conn = nil
				end
			end
			
			def rejoin_client
				# Only if we've registered... Client can connect v. early on in reg process
				# and server complains that we're not yet registered when we send NAMES/TOPIC
				if IRCBouncer.server_registered?(@server.name, @user.name)
					# MOTD...
					relay("MOTD")
					# Convince the client that it's connected to the rooms
					@server_conn.channels.each{ |c| send(":#{@server_conn.nick}!~#{@server_conn.name}@#{@server_conn.servername} JOIN #{c.name}") }
					# Ask for the topics of all joined rooms
					@server_conn.channels.each{ |c| relay("TOPIC #{c.name}") }
					# Ask for the names of joined channels
					@server_conn.channels.each{ |c| relay("NAMES #{c.name}") }
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
				unless @server_conn
					msg_client("You're not connected to a server. Use /relay help for help")
					return
				end
				channel = @server_conn.channels.first(:name => "##{channel_name}")
				unless channel
					new_channel = Channel.first_or_create(:name => "##{channel_name}", :server => @server)
					@server_conn.channels << new_channel
					@server_conn.save
				end
				relay("JOIN ##{channel_name}")
			end
			
			def change_nick(nick, data)
				@nick = nick
				if @server_conn
					@server_conn.update(:nick => @nick)
					relay(data)
				end
				log("NICK #{nick}")
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
				@server = @server_conn = nil if server == @server
			end
			
			def msg_client(message)
				send(":IRCRelay!IRCRelay@ircrelay. NOTICE #{@nick} :#{message}")
			end
			
			def list_servers
				if Server.all.empty?
					msg_client("There are no configured servers")
					msg_client(@user.level == :admin ? "Use /relay create to create new servers" : "Get an admin to create some")
					return
				end
				msg_client("Available servers are:")
				Server.all.each do |server|
					msg = " - #{server.name}   #{server.address}:#{server.port}"
					if IRCBouncer.client_connected?(server.name, @user.name)
						msg << "  (connected" 
						msg << (@server == server ? ", current)" : ")")
					end
					msg_client(msg)
				end
			end
			
			def create_server(parts)
				unless IRCBouncer.config['user.can_create_servers'] || @user.level == :admin
					msg_client("You're not allowed to do that")
					return
				end
				server = Server.new(:name => parts[:name], :address => parts[:address], :port => parts[:port])
				if server.save
					msg_client("Server #{parts[:name]} created")
					log("Create server #{parts[:name]}")
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
				log("Delete server #{name}")
			end
			
			def create_user(name, pass, is_admin)
				user = User.new(:name => name, :server_pass => pass, :level => (is_admin ? :admin : :user))
				if user.save
					msg_client("#{is_admin ? "Admin" : "User"} #{name} created")
					log("Create #{is_admin ? "Admin" : "User"} #{name}")
					return user
				else
					msg_client("Failed: #{user.errors.to_a.join(', ')}")
				end
				return false
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
				log("Delete user #{name}")
			end
			
			def change_pass(pass)
				@user.update(:server_pass => pass)
				msg_client("Password changed to #{pass}")
			end
			
			def add_join_command(cmd)
				return if @server_conn.join_commands.count(:command => cmd) > 0
				@server_conn.join_commands.create(:command => cmd)
			end
			
			def relay_cmd(cmd)
				case cmd
				when /^LIST$/i
					list_servers
				when /^CONNECT\s(?<server>.+)$/i
					create_server_conn($~[:server])
				when /^QUIT(?:\s(?<server>.+))?$/i
					quit_server($~[:server])
				when /^QUIT/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^CREATE\s(?<name>.+?)\s(?<address>.+?):(?<port>\d+)$/i
					create_server($~)
				when /^CREATE/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^DELETE\s(?<name>.+)$/i
					delete_server($~[:name]) if check_is_admin
				when /^DELETE/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^CREATE_(?<type>USER|ADMIN)\s(?<name>.+?)\s(?<pass>.+)$/i
					create_user($~[:name], $~[:pass], $~[:type].downcase == 'admin') if check_is_admin
				when /^CREATE_(USER|ADMIN)/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^DELETE_USER\s(?<name>.+)$/i
					delete_user($~[:name]) if check_is_admin
				when /^DELETE_USER/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^CHANGE_PASS\s(?<pass>.+)$/i
					change_pass($~[:pass])
				when /^CHANGE_PASS/i
					msg_client("Incorrect syntax. Use /relay help to view help")
				when /^HELP/i
					show_help
				else
					msg_client("Command #{cmd} not recognised")
				end
			end
			
			def show_help
				msg_client("All commands have the form /relay <command>")
				msg_client("Possible commands are:")
				msg_client("  connect <server_name>")
				msg_client("      - Connects to a new server")
				msg_client("  quit [<server_name>]")
				msg_client("      - Leaves the named server, or the current server if none specified")
				if @user.level == :admin || IRCBouncer.config['user.can_create_servers']
					msg_client("  create <server_name> <server_address>:<server_port>")
					msg_client("      - Creates a new server with the given name, address, and port")
				end
				if @user.level == :admin
					msg_client("  delete <server_name>")
					msg_client("      - Deletes the server with that name")
					msg_client("  create_user <name> <pass>")
					msg_client("      - Creates a new user")
					msg_client("  create_admin <name> <pass>")
					msg_client("      - Creates a new admin")
					msg_client("  delete_user <name>")
					msg_client("      - Deletes the specified user")
				end
				msg_client("  change_pass <new_pass>")
				msg_client("      - Changes your server password")
			end
			
			def check_is_admin
				return true if @user.level == :admin
				msg_client("You need to be an admin to do that")
				return false
			end

			def send(data)
				log("--> (Server) #{data}") if @verbose
				send_data(data << "\n")
			end
			
			def relay(data)
				IRCBouncer.data_from_client(@server.name, @user.name, data) if @server && @user
			end
			
			def close_client(msg=nil)
				msg_client(msg) if msg
				msg_client("Disconnecting...")
				# For some reason, a small amount of time is needed
				sleep(0.1)
				close_connection_after_writing
				true
			end
			
			def ping
				if @ping_count > 5
					close_client("You missed 5 pings")
					return
				end
				send("PING :irc.antonymale.co.uk")
				@ping_count += 1
			end
			
			def log(msg)
				name = @user ? @user.name : nil
				server = @server ? @server.name : nil
				if name && server
					puts "#{name}, #{server}: #{msg}"
				elsif server
					puts "#{server}: #{msg}"
				else
					puts msg
				end
			end
		end
	end
end