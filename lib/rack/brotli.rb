require 'rack'
require 'git-version-bump'
require 'rack/brotli/deflater'

module Rack
  module Brotli
    def self.release
      GVB.version
    end

    def self.new(app, options={})
      Rack::Brotli::Deflater.new(app, options)
    end
  end

  autoload :Brotli, "rack/brotli/deflater"
end
