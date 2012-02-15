class JoinCommand
	include DataMapper::Resource
	
	property :id, Serial
	property :cmd, String
	
	belongs_to :server
	belongs_to :user
end