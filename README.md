# ms_fabric

A small, read-only Ruby client for **Microsoft Fabric**. Connect to Fabric services and get
results back as plain Ruby — no framework, no ActiveRecord.

Supported today:

| Class | Talks to | Transport |
|---|---|---|
| `MsFabric::Lakehouse::Database` | Lakehouse **tables** (SQL analytics endpoint) | T-SQL over ODBC |
| `MsFabric::Lakehouse::Files` | Lakehouse **files** (OneLake) | ADLS Gen2 over HTTPS |
| `MsFabric::Eventhouse::Database` | Eventhouse **KQL database** | Kusto REST |

All clients inherit auth from the base `MsFabric` class. **Read-only** — writes and control
commands are rejected.

## Install

```ruby
gem "ms_fabric", git: "git@github.com:bornwest/ms_fabric.git"
```

`ruby-odbc` is bundled as a dependency (no separate install), but its native extension needs
**unixODBC** to compile and the **Microsoft ODBC Driver 18** (`msodbcsql18`) on the host to connect
— both required only for `MsFabric::Lakehouse::Database` (the SQL endpoint). On Debian/Ubuntu:

```dockerfile
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list > /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*
```

Eventhouse and OneLake files use only the Ruby standard library — the ODBC extension is loaded
lazily, so those paths work even where the driver isn't installed.

## Authentication

Every client takes the same auth options. Pass **service-principal** credentials, or rely on a
**managed identity** (used automatically when no client credentials are given and an identity
endpoint is present — e.g. on Azure App Service). Read every value from configuration/ENV — never
hardcode credentials or resource names.

```ruby
sp = { client_id: ENV.fetch("AZURE_CLIENT_ID"),
       client_secret: ENV.fetch("AZURE_CLIENT_SECRET"),
       tenant_id: ENV.fetch("AZURE_TENANT_ID") }

# On App Service, pass nothing — the managed identity is picked up from IDENTITY_ENDPOINT.
```

## Usage

### Eventhouse (KQL)

```ruby
eh = MsFabric::Eventhouse::Database.new(
  cluster_uri: ENV.fetch("FABRIC_EVENTHOUSE_URI"),
  database:    ENV.fetch("FABRIC_EVENTHOUSE_DB"),
  **sp)

eh.query("<table> | take 10")                 # => [{ "col" => value, ... }, ...]
eh.query("<table> | count") { |row| ... }     # streams rows, returns the count
```

### Lakehouse tables (SQL endpoint)

```ruby
db = MsFabric::Lakehouse::Database.new(
  sql_endpoint: ENV.fetch("FABRIC_SQL_ENDPOINT"),   # <name>.datawarehouse.fabric.microsoft.com
  database:     ENV.fetch("FABRIC_LAKEHOUSE_DB"),
  **sp)

db.query("SELECT TOP 10 col_a, col_b FROM my_table")   # => [{ "col_a" => ..., ... }]
db.close   # release the ODBC connection when done
```

### Lakehouse files (OneLake)

```ruby
files = MsFabric::Lakehouse::Files.new(
  workspace: ENV.fetch("FABRIC_WORKSPACE"),
  lakehouse: ENV.fetch("FABRIC_LAKEHOUSE"),
  **sp)

files.list_files("path/to/dir")                     # paginated; => [{ "name"=>..., "size"=>..., ... }]
files.list_files("path/to/dir", limit: 100)         # cap entries
bytes = files.read_file("path/to/dir/file.pdf")
files.read_file("path/to/big.zip") { |chunk| io.write(chunk) }   # streamed, returns nil
```

## Return shapes & limits

- **Queries** return `Array<Hash>` with string keys; pass a block to stream rows instead of
  materializing them (returns the row count).
- **`limit:`** on `query`/`list_files` caps how many rows/entries are materialized (client-side).
  It does not reduce server-side work — bound the query itself (`TOP`, `take`) for that.
- **`read_file`** returns bytes, or streams chunks to a block.
- **`list_files`** paginates ADLS continuation tokens, so large directories return in full.

## Errors

All raised errors subclass `MsFabric::Error`:

| Class | Raised when |
|---|---|
| `MsFabric::AuthError` | token acquisition failed (bad creds, missing identity, non-200) |
| `MsFabric::ConnectionError` | host unreachable / socket / TLS failure (SQL connect included) |
| `MsFabric::TimeoutError` | an open/read timed out (subclass of `ConnectionError`) |
| `MsFabric::QueryError` | server returned an error, or a read-only violation |
| `MsFabric::ProtocolError` | unexpected or unparseable response |

Requests carry sane timeouts and retry transient failures (`429/5xx`, network blips) with backoff.

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT
