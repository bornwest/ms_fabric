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

      # SELECT -> Array<Hash> (string keys); with a block, streams each row and returns the count.
      def query(sql, &block)
        guard_read_only!(sql)
        MsFabric.load_odbc!
        stmt = connection.run(sql)
        return stream(stmt, &block) if block

        [].tap { |rows| stmt.each_hash { |row| rows << row.dup } }
      ensure
        stmt&.drop
      end

      def close
        @connection&.disconnect
        @connection = nil
      end

      private

      def stream(stmt)
        count = 0
        stmt.each_hash { |row| yield row.dup; count += 1 }
        count
      end

      def connection
        @connection ||= ODBC::Database.new.drvconnect(connection_string)
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
