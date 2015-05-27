Gem::Specification.new do |s|
  s.name        = 'sinatra-rate-limiter'
  s.version     = '0.1.1'
  s.licenses    = ['MIT']
  s.summary     = 'A redis based rate limiter for Sinatra'
  s.description = 'A redis based rate limiter for Sinatra'
  s.authors     = ['Warren Guy']
  s.email       = 'warren@guy.net.au'
  s.homepage    = 'https://github.com/warrenguy/sinatra-rate-limiter'

  s.files       = Dir['README.md', 'LICENSE', 'lib/**/*']

  s.add_dependency('sinatra', '~> 1.3')
  s.add_dependency('redis',   '~> 3.0')
end
