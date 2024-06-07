# frozen_string_literal: true

require 'brotli'
require "rack/utils"
require 'rack/request'
require 'rack/body_proxy'

module Rack::Brotli
  # This middleware enables compression of http responses with the `br` encoding,
  # when support is detected and allowed.
  class Deflater
    ##
    # Creates Rack::Brotli middleware.
    #
    # [app] rack app instance
    # [options] hash of deflater options, i.e.
    #           'if' - a lambda enabling / disabling deflation based on returned boolean value
    #                  e.g use Rack::Brotli, :if => lambda { |env, status, headers, body| body.map(&:bytesize).reduce(0, :+) > 512 }
    #           'include' - a list of content types that should be compressed
    #           'deflater' - Brotli compression options Hash (see https://brotli.org/encode.html#a4d4 and https://github.com/miyucy/brotli/blob/ea0e058031177e5cc42e361f7d2702a951048a31/ext/brotli/brotli.c#L119-L180)
    #              - 'mode'
    #              - 'quality'
    #              - 'lgwin'
    #              - 'lgblock'
    def initialize(app, options = {})
      @app = app

      @condition = options[:if]
      @compressible_types = options[:include]
      @deflater_options = { quality: 5 }.merge(options.fetch(:deflater, {}))
      @sync = options.fetch(:sync, true)
    end

    def call(env)
      status, headers, body = response = @app.call(env)

      unless should_deflate?(env, status, headers, body)
        return response
      end

      request = Rack::Request.new(env)

      encoding = Rack::Utils.select_best_encoding(%w(br identity), request.accept_encoding)

      # Set the Vary HTTP header.
      vary = headers["vary"].to_s.split(",").map(&:strip)
      unless vary.include?("*") || vary.any?{|v| v.downcase == 'accept-encoding'}
        headers["vary"] = vary.push("Accept-Encoding").join(",")
      end

      case encoding
      when "br"
        headers['content-encoding'] = "br"
        headers.delete(Rack::CONTENT_LENGTH)
        response[2] = BrotliStream.new(body, @sync, @deflater_options)
        response
      when "identity"
        response
      else
        # Only possible encoding values here are 'br', 'identity', and nil
        message = "An acceptable encoding for the requested resource #{request.fullpath} could not be found."
        bp = Rack::BodyProxy.new([message]) { body.close if body.respond_to?(:close) }
        [406, { Rack::CONTENT_TYPE => "text/plain", Rack::CONTENT_LENGTH => message.length.to_s }, bp]
      end
    end

    # Body class used for encoded responses.
    class BrotliStream

      BUFFER_LENGTH = 128 * 1_024

      def initialize(body, sync, br_options)
        @body = body
        @br_options = br_options
        @sync = sync
      end

      # Yield compressed strings to the given block.
      def each(&block)
        @writer = block
        br = Brotli::Writer.new(self, @br_options)
        # @body.each is equivalent to @body.gets (slow)
        if @body.is_a? ::File # XXX: Should probably be ::IO
          while part = @body.read(BUFFER_LENGTH)
            br.write(part)
            br.flush if @sync
          end
        else
          @body.each { |part|
            # Skip empty strings, as they would result in no output,
            # and flushing empty parts could raise an IO error.
            next if part.empty?
            br.write(part)
            br.flush if @sync
          }
        end
      ensure
        br.finish
      end

      # Call the block passed to #each with the compressed data.
      def write(data)
        @writer.call(data)
      end

      # Close the original body if possible.
      def close
        @body.close if @body.respond_to?(:close)
      end
    end

    private

    # Whether the body should be compressed.
    def should_deflate?(env, status, headers, body)
      # Skip compressing empty entity body responses and responses with
      # no-transform set.
      if Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.key?(status.to_i) ||
        /\bno-transform\b/.match?(headers[Rack::CACHE_CONTROL].to_s) ||
        headers['content-encoding']&.!~(/\bidentity\b/)
        return false
      end

      # Skip if @compressible_types are given and does not include request's content type
      return false if @compressible_types && !(headers.has_key?(Rack::CONTENT_TYPE) && @compressible_types.include?(headers[Rack::CONTENT_TYPE][/[^;]*/]))

      # Skip if @condition lambda is given and evaluates to false
      return false if @condition && !@condition.call(env, status, headers, body)

      # No point in compressing empty body, also handles usage with
      # Rack::Sendfile.
      return false if headers[Rack::CONTENT_LENGTH] == '0'

      true
    end
  end
end
