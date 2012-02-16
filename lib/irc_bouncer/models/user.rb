class User
	include DataMapper::Resource
	
	property :id, Serial
	property :name, String
	property :server_pass, String
	property :level, Enum[:admin, :user], :default => :user

	has n, :join_commands
	has n, :server_conns
	
	def servers
		channels.all.inject([]){ |s,c| s << c.server }.uniq
	end
end