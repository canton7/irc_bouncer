class Server
	include DataMapper::Resource
	
	property :id, Serial
	property :name, String, :unique => true
	property :address, String
	property :port, Integer
	
	has n, :channels
end