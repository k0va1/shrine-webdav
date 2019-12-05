# frozen_string_literal: true

require 'shrine'
require 'http'
require 'down/http'

class Shrine
  module Storage
    class WebDAV
      def initialize(host:, prefix: nil, upload_options: {}, credentials: {})
        @host           = host
        @prefix         = prefix
        @prefixed_host  = path(@host, @prefix)
        @upload_options = upload_options
        @credentials    = credentials
      end

      def upload(io, id, shrine_metadata: {}, **upload_options)
        options = current_options(upload_options)
        mkpath_to_file(id) unless options[:create_full_put_path]
        put(id, io)
      end

      def url(id, **options)
        path(@prefixed_host, id)
      end

      def open(id)
        if @credentials.empty?
          Down::Http.open(path(@prefixed_host, id))
        else
          Down::Http.open(
            path(@prefixed_host, id),
            headers: { 'Authorization' => 'Basic ' + Base64.strict_encode64("#{@credentials[:user]}:#{@credentials[:pass]}") }
          )
        end
      end

      def exists?(id)
        response = client.head(path(@prefixed_host, id))
        (200..299).cover?(response.code.to_i)
      end

      def delete(id)
        client.delete(path(@prefixed_host, id))
      end

      private

      def client
        return @client if @client

        if @credentials.empty?
          @client = HTTP::Client.new
        else
          @client = HTTP.basic_auth(user: @credentials[:user], pass: @credentials[:pass])
        end
      end

      def current_options(upload_options)
        options = {}
        options.update(@upload_options)
        options.update(upload_options)
      end

      def put(id, io)
        uri      = path(@prefixed_host, id)
        response = client.put(uri, body: io)
        return if (200..299).cover?(response.code.to_i)
        raise Error, "uploading of #{uri} failed, the server response was #{response}"
      end

      def path(host, uri)
        (uri.nil? || uri.empty?) ? host : [host, uri].compact.join('/')
      end

      def mkpath_to_file(path_to_file)
        @prefix_created ||= create_prefix
        last_slash      = path_to_file.rindex('/')
        if last_slash
          path = path_to_file[0..last_slash]
          mkpath(@prefixed_host, path)
        end
      end

      def create_prefix
        mkpath(@host, @prefix) unless @prefix.nil? || @prefix.empty?
      end

      def mkpath(host, path)
        dirs = []
        path.split('/').each do |dir|
          dirs << "#{dirs[-1]}/#{dir}"
        end
        dirs.each do |dir|
          response = client.request(:mkcol, "#{host}#{dir}")
          unless (200..301).cover?(response.code.to_i)
            raise Error, "creation of directory #{host}#{dir} failed, the server response was #{response}"
          end
        end
      end
    end
  end
end
