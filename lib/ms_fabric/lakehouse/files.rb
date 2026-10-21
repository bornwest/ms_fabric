class MsFabric
  module Lakehouse
    # Reads and writes OneLake files (ADLS Gen2 over HTTPS) in a lakehouse's Files/ area.
    class Files < MsFabric
      RESOURCE = "https://storage.azure.com".freeze
      HOST = "onelake.dfs.fabric.microsoft.com".freeze
      FILE_READ_TIMEOUT = 300
      API_VERSION = "2023-11-03".freeze
      CHUNK = 4 * 1024 * 1024

      def initialize(workspace:, lakehouse:, **auth)
        super(**auth)
        @workspace = workspace
        @lakehouse = lakehouse
      end

      # List files under a Files/ subpath (paginates continuation tokens). Returns Array<Hash>:
      # name, size, last_modified, is_directory. `dir` is relative to Files/ ("" = whole area);
      # `limit` caps the number of entries returned.
      def list_files(dir = "", recursive: true, limit: nil)
        directory = ["#{@lakehouse}.Lakehouse/Files", dir].reject { |s| s.to_s.empty? }.join("/")
        results = []
        continuation = nil
        loop do
          res = list_request(directory, recursive, continuation)
          Http.json(res).fetch("paths", []).each do |p|
            results << { "name" => p["name"], "size" => p["contentLength"]&.to_i,
                         "last_modified" => p["lastModified"], "is_directory" => p["isDirectory"] == "true" }
            return results if limit && results.size >= limit
          end
          continuation = res["x-ms-continuation"]
          break if continuation.nil? || continuation.empty?
        end
        results
      end

      # Download a file (`path` relative to Files/). Returns bytes, or with a block streams them in
      # chunks (nothing buffered) and returns nil.
      def read_file(path, &block)
        uri = file_uri(path)
        return download_stream(uri, &block) if block

        res = Http.request(uri, authed_get(uri), read_timeout: FILE_READ_TIMEOUT)
        ok!(res)
        res.body
      end

      # Write `io` (an IO, or a String of bytes) to `path` relative to Files/, replacing any file
      # there; parent folders are created. The bytes are appended in CHUNK pieces and committed by
      # the final flush, so a reader never sees a partial file. Returns the number of bytes written.
      #
      # The requests share one connection: OneLake answers the first request on a connection
      # seconds slower than the rest.
      def write_file(path, io)
        io = StringIO.new(io) if io.is_a?(String)
        uri = file_uri(path)
        Http.session(uri, read_timeout: FILE_READ_TIMEOUT) do |http|
          write_request(http, :Put, uri, "resource=file")
          position = 0
          while (chunk = io.read(CHUNK))
            write_request(http, :Patch, uri, "action=append&position=#{position}", chunk)
            position += chunk.bytesize
          end
          write_request(http, :Patch, uri, "action=flush&position=#{position}")
          position
        end
      end

      private

      def write_request(http, method, uri, query, body = "")
        uri = uri.dup.tap { |u| u.query = query }
        req = Net::HTTP.const_get(method).new(uri)
        req["Authorization"] = "Bearer #{token(RESOURCE)}"
        req["x-ms-version"] = API_VERSION
        req.body = body
        ok!(Http.request(uri, req, read_timeout: FILE_READ_TIMEOUT, http:))
      end

      def list_request(directory, recursive, continuation)
        uri = URI("https://#{HOST}/#{enc(@workspace)}")
        params = { resource: "filesystem", recursive:, directory: }
        params[:continuation] = continuation if continuation
        uri.query = URI.encode_www_form(params)
        res = Http.request(uri, authed_get(uri))
        ok!(res)
        res
      end

      def download_stream(uri)
        Http.stream(uri, authed_get(uri), read_timeout: FILE_READ_TIMEOUT) do |res|
          ok!(res)
          res.read_body { |chunk| yield chunk }
        end
        nil
      end

      def file_uri(path)
        segs = path.split("/").map { |s| enc(s) }.join("/")
        URI("https://#{HOST}/#{enc(@workspace)}/#{enc("#{@lakehouse}.Lakehouse")}/Files/#{segs}")
      end

      def authed_get(uri)
        Net::HTTP::Get.new(uri).tap { |req| req["Authorization"] = "Bearer #{token(RESOURCE)}" }
      end

      def ok!(res)
        raise QueryError, "OneLake #{res.code}: #{res.body.to_s[0, 300]}" unless res.code.to_i.between?(200, 299)
      end

      def enc(str) = ERB::Util.url_encode(str)
    end
  end
end
