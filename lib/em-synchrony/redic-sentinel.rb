require 'redic/connection/synchrony' unless defined? Redic::Connection::Synchrony
require 'redic-sentinel'

class Redic::Client
  class_eval do
    private
    def sleep(seconds)
      f = Fiber.current
      EM::Timer.new(seconds) { f.resume }
      Fiber.yield
    end
  end
end
