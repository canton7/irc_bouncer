class User
	include DataMapper::Resource
	
	property :id, Serial
	property :name, String, :unique => true
	property :server_pass, String, :required => true
	property :level, Enum[:admin, :user], :default => :user

	has n, :server_conns
	
	def servers
		channels.all.inject([]){ |s,c| s << c.server }.uniq
	end
end