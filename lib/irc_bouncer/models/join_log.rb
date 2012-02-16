class JoinLog
	include DataMapper::Resource
	
	property :id, Serial
	property :message, String, :length => 1..200
	
	belongs_to :server_conn
end