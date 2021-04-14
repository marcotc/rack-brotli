require 'minitest/autorun'
require 'rack/brotli'

describe Rack::Brotli do
  it '#release' do
    _(Rack::Brotli.release).must_equal(Rack::Brotli::Version.to_s)
  end
end
