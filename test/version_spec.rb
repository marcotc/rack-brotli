require 'minitest/autorun'
require 'rack/brotli/version'

describe Rack::Brotli::Version do
  it '#to_s' do
    _(Rack::Brotli::Version.to_s).must_equal('2.0.0')
  end
end
