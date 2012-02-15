class Server
	include DataMapper::Resource
	
	property :id, Serial
	property :name, String
	property :address, String
	property :port, Integer
	
	has n, :channels
end