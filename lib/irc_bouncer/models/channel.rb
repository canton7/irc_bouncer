class Channel
	include DataMapper::Resource
	
	property :id, Serial
	property :name, String
	
	belongs_to :server
	has n, :server_conns, :through => Resource
end