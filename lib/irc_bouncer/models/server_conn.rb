class ServerConn
	include DataMapper::Resource
	
	property :id, Serial
	property :host, String
	property :servername, String
	property :name, String
	property :nick, String
	property :preferred_nick, String
	property :nickserv_pass, String
	
	belongs_to :user
	belongs_to :server
	has n, :channels, :through => Resource
	has n, :join_commands
end