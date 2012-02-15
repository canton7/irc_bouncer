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
			@nick
			
			def initialize(*args)
				super
				puts "IRC Server New Connection"
				EventMachine::PeriodicTimer.new(60){ ping }
				@ping_state = :received
			end
			
			# Callbacks
			
			def receive_line(data)
				handle(data)
			end
			
			def unbind
				puts "IRC Server Connection Died"
			end
			
			# Methods
			
			def handle(data)
				puts "<-- (Server) #{data}"
				case data
				when /^NICK (?<nick>.+?)$/
				@nick = $~[:nick]
				when /^USER (?<user>.+?)\s"(?<host>.+?)"\s"(?<server>.+?)"\s:(?<name>.+?)$/
				identify_user($~)
				else
				relay(data)
				end
			end
			
			def identify_user(parts)
				@user, @server = parts[:user].split('@')
				# TODO proper exception handling
				unless @server
					puts "Invalid name (no server)"
					close_connection
				end
				IRCBouncer.connect_client(self, @server, @user)
				relay("NICK #{@nick}")
				relay("USER #{@user} \"#{parts[:host]}\" \"#{parts[:server]}\" :#{parts[:name]}")
			end
			
			def send(data)
				puts "--> (Server) #{data}"
				send_data(data << "\n")
			end
			
			def relay(data)
				IRCBouncer.data_from_client(@server, @nick, data) if @server && @nick
			end
			
			def ping
				puts "NO RESPONSE" unless @ping_state == :received
				send("PING :irc.antonymale.co.uk")
				@ping_state = :sent
			end
		end
	end
end