require 'eventmachine'

module IRCBouncer
	class IRCServer
		@server
		@port
		
		def initialize(server, port)
				@server, @port = server, port
		end
		
		def run!
			EventMachine::run do
				EventMachine::start_server(@server, @port, Handler)
				#EventMachine::add_periodic_timer(1){ send_data "PING" }
				puts "Server started "
			end
		end
		
		class Handler < EventMachine::Connection
			@ping_state
			def initialize(*args)
				super
				puts "New connection"
				EventMachine::PeriodicTimer.new(60){ ping }
				@ping_state = :received
			end
			
			# Callbacks
			
			def receive_data(data)
				data.each_line{ |d| handle(d) }
			end
			
			def unbind
				puts "Connection died"
			end
			
			def send_data(data)
				super
				puts "--> #{data}"
			end
			
			# Methods
			
			def handle(data)
				puts "<-- #{data}"
			end
			
			def ping
				puts "NO RESPONSE" unless @ping_state == :received
				send_data "PING :irc.antonymale.co.uk"
				@ping_state = :sent
			end
		end
	end
end

IRCBouncer::IRCServer.new('localhost', 1234).run!