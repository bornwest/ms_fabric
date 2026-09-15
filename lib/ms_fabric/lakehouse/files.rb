class MsFabric
  module Lakehouse
    # Reads OneLake files (ADLS Gen2 over HTTPS) for a lakehouse's Files/ area.
    class Files < MsFabric
      RESOURCE = "https://storage.azure.com".freeze
      HOST = "onelake.dfs.fabric.microsoft.com".freeze
      FILE_READ_TIMEOUT = 300

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

      private

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
