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
			
			def initialize(*args)
				super
				puts "IRC Client is Connected"
			end
			
			def init(server, server_conn, user)
				@server, @server_conn, @user = server, server_conn, user
				join_server
			end
			
			def receive_line(data)
				puts "<-- (Client) #{data}"
				handle(data.chomp)
			end
			
			def unbind
				puts "IRC Client is Disconnected"
				IRCBouncer.server_died(@server, @nick)
			end
			
			def handle(data)
				case data
				when /^:(?<server>.+?)\s(?<code>\d{3})\s(?<nick>.+?)\s(?<message>.+)$/
					numeric_message($~[:code].to_i, data)
				when /^:(?<stuff>.+?)\sJOIN\s#(?<channel>.+)$/
					join_channel($~, data)
				when /^PING (?<server>.+)$/
					send("PONG #{$~[:server]}")
				when /^:(?<stuff>.+?)\sPART\s#(?<channel>.+)$/
					part_channel($~)
				when /^:(?<stuff>.+?)\s(?<type>PRIVMSG)\s(?<dest>.+?)\s:(?<message>.+)$/
					message($~, data)
				else
					relay(data)
				end
			end
			
			def send(data)
				puts "--> (Client) #{data}"
				data.split("\n").each{ |l| send_data(l << "\n") }
			end

			def join_server
				return if IRCBouncer.client_connected?(@server.name, @user.name)
				# Delete the join messages from last time
				JoinLog.all(:server_conn => @server_conn).destroy!
				send("USER #{@user.name} \"#{@server_conn.host}\" \"#{@server_conn.servername}\" :#{@server_conn.name}")
				send("NICK #{@server_conn.nick}")
				@server_conn.channels.each do |channel|
					send("join #{channel.name}")
				end
			end
			
			def numeric_message(code, data)
				case code
				# MOTD
				when 372, 375, 376, 377
					if IRCBouncer.client_connected?(@server.name, @user.name)
						relay(data)
					else
						JoinLog.create(:message => data, :server_conn => @server_conn)
					end
				else
					relay(data) if IRCBouncer.client_connected?(@server.name, @user.name)
				end
			end
			
			def join_channel(parts, data)
				if IRCBouncer.client_connected?(@server.name, @user.name)
					relay(data)
				else
					JoinLog.create(:message => data, :server_conn => @server_conn)
				end
			end
			
			def part_channel(parts)
				@server_conn.channels.delete_if{ |c| c.name == "##{parts[:channel]}" }
				@server_conn.save
				relay(":#{parts[:stuff]} PART ##{parts[:channel]}")
			end
			
			def message(parts, data)
				puts "IS THE CLIENT STILL AROUND?"
				p IRCBouncer.client_connected?(@server.name, @user.name)
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
		end
	end
end