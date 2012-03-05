class JoinCommand
	include DataMapper::Resource

	property :id, Serial
	property :command, String, :length => 1..512

	belongs_to :server_conn
end