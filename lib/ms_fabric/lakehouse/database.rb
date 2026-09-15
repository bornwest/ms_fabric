class MsFabric
  module Lakehouse
    # Read-only T-SQL over a Lakehouse SQL analytics endpoint (TDS via ODBC). The ODBC driver
    # performs the Entra login itself — service principal locally, managed identity on Azure.
    class Database < MsFabric
      def initialize(sql_endpoint:, database:, **auth)
        super(**auth)
        @sql_endpoint = sql_endpoint
        @database = database
      end

      # SELECT -> Array<Hash> (string keys). `limit` caps rows read (client-side). With a block,
      # streams each row and returns the count.
      def query(sql, limit: nil, &block)
        guard_read_only!(sql)
        MsFabric.load_odbc!
        fetch_rows(sql, limit, &block)
      end

      def close = reset_connection

      private

      # ODBC constants are referenced only here, after load_odbc! has required the extension.
      def fetch_rows(sql, limit, &block)
        stmt = connection.run(sql)
        block ? stream(stmt, limit, &block) : collect(stmt, limit)
      rescue ODBC::Error => e
        reset_connection
        raise QueryError, "SQL query failed: #{e.message}"
      ensure
        stmt&.drop
      end

      def collect(stmt, limit)
        rows = []
        stmt.each_hash do |row|
          rows << row.dup
          break if limit && rows.size >= limit
        end
        rows
      end

      def stream(stmt, limit)
        count = 0
        stmt.each_hash do |row|
          yield row.dup
          count += 1
          break if limit && count >= limit
        end
        count
      end

      def connection
        @connection ||= ODBC::Database.new.drvconnect(connection_string)
      rescue ODBC::Error => e
        @connection = nil
        raise ConnectionError, "SQL connect failed: #{e.message}"
      end

      def reset_connection
        @connection&.disconnect
      rescue ODBC::Error
        nil # already dead
      ensure
        @connection = nil
      end

      def connection_string
        "Driver={ODBC Driver 18 for SQL Server};Server=#{@sql_endpoint},1433;" \
          "Database=#{@database};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" +
          auth_clause
      end

      def auth_clause
        if service_principal?
          "Authentication=ActiveDirectoryServicePrincipal;UID=#{client_id};PWD=#{client_secret};"
        else
          "Authentication=ActiveDirectoryMsi;"
        end
      end

      def guard_read_only!(sql)
        return if sql.strip.match?(/\A(select|with)\b/i)

        raise QueryError, "read-only: only SELECT/WITH queries are allowed"
      end
    end
  end
end
