# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redic-sentinel/version'

Gem::Specification.new do |gem|
  gem.name          = "redic-sentinel"
  gem.version       = Redic::Sentinel::VERSION
  gem.authors       = ["Richard Huang", "Phuong Gia Su"]
  gem.email         = ["flyerhzm@gmail.com", "phuongnd08@gmail.com"]
  gem.description   = %q{automatic master/slave failover solution for redic by using built-in redis sentinel}
  gem.summary       = %q{automatic master/slave failover solution for redic by using built-in redis sentinel}
  gem.homepage      = "https://github.com/phuongnd08/redic-sentinel"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "redic"
  gem.add_dependency "redis"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "eventmachine"
  gem.add_development_dependency "em-synchrony"
  gem.add_development_dependency "hiredis"
end
