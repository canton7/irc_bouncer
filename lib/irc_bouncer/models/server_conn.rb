class ServerConn
	include DataMapper::Resource
	
	property :id, Serial
	property :host, String
	property :servername, String
	property :name, String
	property :nick, String
	
	belongs_to :user
	belongs_to :server
	has n, :channels, :through => Resource
	has n, :join_commands
end