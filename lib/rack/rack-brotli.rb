require 'rack'
require 'git-version-bump'

module Rack
  module Brotli
    def self.release
      GVB.version
    end
  end

  autoload :Brotli, "rack/brotli/deflater"
end
