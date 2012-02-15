class User
	include DataMapper::Resource
	
	property :id, Serial
	property :nick, String
	property :server_pass, String
	
	has n, :channels, :through => Resource
	
	def servers
		channels.all.inject([]){ |s,c| s << c.server }.uniq
	end
end