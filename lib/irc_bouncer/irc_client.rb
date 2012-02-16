module IRCBouncer
	class IRCClient
		@server
		@server_conn
		@user
		
		def initialize(server_conn, user)
			@server_conn, @user = server_conn, user
			@server = @server_conn.server
		end
		
		def run!
			EventMachine::connect(@server.address, @server.port, Handler) do |c|
				c.init(@server, @server_conn, @user)
				return c
			end
		end
		
		class Handler < EventMachine::Connection
			include EventMachine::Protocols::LineText2
			
			# Name of the server we're the connection to, and
			# nick of the person we're the connection for
			@server
			@server_conn
			@user
			@registered
			@verbose
			
			def initialize(*args)
				super
				@registered = false
				@verbose = IRCBouncer.config['server.verbose']
			end
			
			def init(server, server_conn, user)
				@server, @server_conn, @user = server, server_conn, user
				puts "Connected to IRC server: #{@server.name} (#{@server.address}:#{@server.port})"
				join_server
			end
			
			def registered?; @registered; end
			
			def receive_line(data)
				puts "<-- (Client) #{data}" if @verbose
				handle(data.chomp)
			end
			
			def unbind
				puts "IRC Client is Disconnected"
				IRCBouncer.server_died(@server.name, @user.name)
			end
			
			def handle(data)
				case data
				when /^:(?<server>.+?)\s(?<code>\d{3})\s(?<nick>.+?)\s(?<message>.+)$/
					numeric_message($~[:code].to_i, $~[:message], data)
				when /^:(?<stuff>#{@server_conn.nick}!~#{@user.name}.+?)\sJOIN\s#(?<channel>.+)$/
					join_channel($~, data)
				when /^PING (?<server>.+)$/
					send("PONG #{$~[:server]}")
				when /^:(?<stuff>#{@server_conn.nick}!~#{@user.name}.+?)\sPART\s#(?<channel>.+)$/
					part_channel($~)
				when /^:(?<stuff>.+?)\s(?<type>PRIVMSG)\s(?<dest>.+?)\s:(?<message>.+)$/
					message($~, data)
				else
					relay(data)
				end
			end
			
			def send(data)
				log("--> (Client) #{data}") if @verbose
				data.split("\n").each{ |l| send_data(l << "\n") }
			end

			def join_server
				return if IRCBouncer.client_connected?(@server.name, @user.name)
				puts "#{@server.name}: Identifying... Nick: #{@server_conn.nick}"
				send("USER #{@user.name} \"#{@server_conn.host}\" \"#{@server_conn.servername}\" :#{@server_conn.name}")
				send("NICK #{@server_conn.nick}")
				@server_conn.join_commands.each do |cmd|
					send(cmd.command)
				end
				@server_conn.channels.each do |channel|
					send("JOIN #{channel.name}")
					log("JOIN #{channel.name}")
				end
			end
			
			def numeric_message(code, message, data)
				case code
				# Registered
				when 1
					@registered = true
					puts "#{@server.name}: Connected"
				# MOTD
				#when 372, 375, 376, 377
				when 474, 475
					channel = message.split(' ').first[1..-1]
					log("Banned/kicked from ##{channel}")
					part_channel(:channel => channel)
					relay(data)
				else
					relay(data) if IRCBouncer.client_connected?(@server.name, @user.name)
				end
			end
			
			def join_channel(parts, data)
				# This is useful later on
				@server_conn.update(:identifier => parts[:stuff])
				relay(data) if IRCBouncer.client_connected?(@server.name, @user.name)
				log("JOIN ##{parts[:channel]}")
			end
			
			def part_channel(parts)
				@server_conn.channels.delete_if{ |c| c.name == "##{parts[:channel]}" }
				@server_conn.save
				log("PART ##{parts[:channel]}")
				relay(":#{parts[:stuff]} PART ##{parts[:channel]}") if parts[:stuff]
			end
			
			def message(parts, data)
				if IRCBouncer.client_connected?(@server.name, @user.name)
					relay(data)
				else
					MessageLog.create(:header => "#{parts[:stuff]} #{parts[:type]} #{parts[:dest]}",
						:message => parts[:message], :server_conn => @server_conn)
				end
			end
			
			def relay(data)
				IRCBouncer.data_from_server(@server.name, @user.name, data)
			end
			
			def log(msg)
				puts "#{@server.name}, #{@user.name}: #{msg}"
			end
		end
	end
end