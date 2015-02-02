require "redic"

class Redic
  def initialize(url = "redis://127.0.0.1:6379", timeout = 10_000_000, options = {})
    @url = url
    @client = Redic::Client.new(url, timeout, options)
    @queue = []
  end

  def url
    @client.uri.to_s
  end
end
