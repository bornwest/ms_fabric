require "ms_fabric"

# The parts of Net::HTTPResponse the gem reads: code, body, and headers by name.
FakeResponse = Struct.new(:code, :body, :headers) do
  def [](name) = headers.to_h[name]
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
