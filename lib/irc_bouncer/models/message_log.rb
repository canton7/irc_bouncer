class MessageLog
	include DataMapper::Resource

	property :id, Serial
	property :timestamp, EpochTime, :default => Proc.new{ DateTime.now }
	property :header, String, :length => 1..512 # Guessed
	property :channel, String, :length => 1..512
	property :message, String, :length => 1..512 # Length from spec

	belongs_to :server_conn
end