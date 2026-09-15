class MsFabric
  module Eventhouse
    # Read-only KQL over an Eventhouse KQL database (Kusto REST).
    class Database < MsFabric
      RESOURCE = "https://kusto.kusto.windows.net".freeze
      READ_TIMEOUT = 300

      def initialize(cluster_uri:, database:, **auth)
        super(**auth)
        @cluster_uri = cluster_uri.chomp("/")
        @database = database
      end

      # KQL -> Array<Hash> (string keys). `limit` caps rows (client-side; the server still returns
      # the full result — use `take`/`limit` in the query to bound it server-side). With a block,
      # yields each row and returns the count.
      def query(kql, limit: nil, &block)
        guard_read_only!(kql)
        columns, rows = result(post(kql))
        rows = rows.first(limit) if limit
        return stream(columns, rows, &block) if block

        rows.map { |row| columns.zip(row).to_h }
      end

      private

      def result(body)
        table = Array(body["Tables"]).first
        raise ProtocolError, "Eventhouse response had no result table" unless table

        columns = Array(table["Columns"]).map { |c| c["ColumnName"] }
        [columns, Array(table["Rows"])]
      end

      def stream(columns, rows)
        rows.each { |row| yield columns.zip(row).to_h }
        rows.size
      end

      def post(kql)
        uri = URI("#{@cluster_uri}/v1/rest/query")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token(RESOURCE)}"
        req["Content-Type"] = "application/json"
        req.body = { db: @database, csl: kql }.to_json
        res = Http.request(uri, req, read_timeout: READ_TIMEOUT)
        raise QueryError, "Eventhouse #{res.code}: #{res.body.to_s[0, 500]}" unless res.code.to_i == 200

        Http.json(res)
      end

      # Control commands (".create", ".drop", …) mutate; queries never start with a dot.
      def guard_read_only!(kql)
        raise QueryError, "read-only: control commands are not allowed" if kql.strip.start_with?(".")
      end
    end
  end
end
