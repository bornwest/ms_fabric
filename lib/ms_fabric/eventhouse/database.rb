class MsFabric
  module Eventhouse
    # Read-only KQL over an Eventhouse KQL database (Kusto REST).
    class Database < MsFabric
      RESOURCE = "https://kusto.kusto.windows.net".freeze

      def initialize(cluster_uri:, database:, **auth)
        super(**auth)
        @cluster_uri = cluster_uri.chomp("/")
        @database = database
      end

      # KQL -> Array<Hash> (string keys); with a block, yields each row and returns the count.
      def query(kql, &block)
        guard_read_only!(kql)
        table = post(kql).fetch("Tables").first   # Table_0 is the primary result set
        columns = table.fetch("Columns").map { |c| c["ColumnName"] }
        rows = table.fetch("Rows")
        return stream(columns, rows, &block) if block

        rows.map { |row| columns.zip(row).to_h }
      end

      private

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
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        raise QueryError, "Eventhouse #{res.code}: #{res.body.to_s[0, 500]}" unless res.code.to_i == 200

        JSON.parse(res.body)
      end

      # Control commands (".create", ".drop", …) mutate; queries never start with a dot.
      def guard_read_only!(kql)
        raise QueryError, "read-only: control commands are not allowed" if kql.strip.start_with?(".")
      end
    end
  end
end
