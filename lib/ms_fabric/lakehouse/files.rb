class MsFabric
  module Lakehouse
    # Reads OneLake files (ADLS Gen2 over HTTPS) for a lakehouse's Files/ area.
    class Files < MsFabric
      RESOURCE = "https://storage.azure.com".freeze
      HOST = "onelake.dfs.fabric.microsoft.com".freeze

      def initialize(workspace:, lakehouse:, **auth)
        super(**auth)
        @workspace = workspace
        @lakehouse = lakehouse
      end

      # List files under a Files/ subpath. Returns Array<Hash>: name, size, last_modified,
      # is_directory. `dir` is relative to Files/ ("" lists the whole area).
      def list_files(dir = "", recursive: true)
        directory = ["#{@lakehouse}.Lakehouse/Files", dir].reject { |s| s.to_s.empty? }.join("/")
        uri = URI("https://#{HOST}/#{enc(@workspace)}")
        uri.query = URI.encode_www_form(resource: "filesystem", recursive:, directory:)
        paths = JSON.parse(get_body(uri)).fetch("paths", [])
        paths.map do |p|
          { "name" => p["name"], "size" => p["contentLength"]&.to_i,
            "last_modified" => p["lastModified"], "is_directory" => p["isDirectory"] == "true" }
        end
      end

      # Download a file. `path` is relative to Files/. Returns the bytes, or with a block streams
      # them in chunks (nothing buffered) and returns nil.
      def read_file(path, &block)
        uri = file_uri(path)
        return stream(uri, &block) if block

        get_body(uri)
      end

      private

      def file_uri(path)
        segs = path.split("/").map { |s| enc(s) }.join("/")
        URI("https://#{HOST}/#{enc(@workspace)}/#{enc("#{@lakehouse}.Lakehouse")}/Files/#{segs}")
      end

      def get_body(uri)
        req = authed_get(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          res = http.request(req)
          raise QueryError, "OneLake #{res.code}: #{res.body.to_s[0, 300]}" unless ok?(res)
          res.body
        end
      end

      def stream(uri)
        req = authed_get(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(req) do |res|
            raise QueryError, "OneLake #{res.code}" unless ok?(res)
            res.read_body { |chunk| yield chunk }
          end
        end
        nil
      end

      def authed_get(uri)
        Net::HTTP::Get.new(uri).tap { |req| req["Authorization"] = "Bearer #{token(RESOURCE)}" }
      end

      def ok?(res) = res.code.to_i.between?(200, 299)

      def enc(str) = ERB::Util.url_encode(str)
    end
  end
end
