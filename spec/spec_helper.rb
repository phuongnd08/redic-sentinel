require "rspec"

require 'coveralls'
Coveralls.wear!

$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/../lib"))
require "redic"
require "redic-sentinel"

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end
