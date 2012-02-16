$LOAD_PATH.unshift(File.dirname(File.expand_path(__FILE__)))
require 'lib/irc_bouncer/version'

spec = Gem::Specification.new do |s|
  s.name = 'irc_bouncer'
  s.version = IRCBouncer::VERSION
  s.summary = 'irc_bouncer: Remain present in your favourite IRC channels, even if your client disconnects'
  s.description = 'Acts as an IRC proxy, allowing you to connect through it to IRC servers. Logs messages for you when you\'re disconnected'
  s.platform = Gem::Platform::RUBY
  s.authors = ['Antony Male']
  s.email = 'antony dot mail at gmail'
  s.required_ruby_version = '>= 1.9.2'

  s.add_dependency 'data_mapper'
  s.add_dependency 'dm-sqlite-adapter'
  s.add_dependency 'dm-validations'
  s.add_dependency 'eventmachine'
  s.add_dependency 'daemons'

  s.executables  = ['irc_bouncer']

  s.files = Dir['{bin,lib}/**/*']

end
