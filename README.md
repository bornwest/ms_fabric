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
 && apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev \
 && rm -rf /var/lib/apt/lists/*
```

Eventhouse and OneLake files use only the Ruby standard library — the ODBC extension is loaded
lazily, so those paths work even where the driver isn't installed.

## Authentication

Every client takes the same auth options. Pass **service-principal** credentials, or rely on a
**managed identity** (used automatically when no client credentials are given and an identity
endpoint is present — e.g. on Azure App Service).

```ruby
sp = { client_id: ENV["AZURE_CLIENT_ID"],
       client_secret: ENV["AZURE_CLIENT_SECRET"],
       tenant_id: ENV["AZURE_TENANT_ID"] }

# On App Service, pass nothing — the managed identity is picked up from IDENTITY_ENDPOINT.
```

## Usage

### Eventhouse (KQL)

```ruby
eh = MsFabric::Eventhouse::Database.new(
  cluster_uri: "https://<cluster>.kusto.fabric.microsoft.com",
  database: "atlas_events",
  **sp)

eh.query("sp_items | take 10")             # => [{ "name" => "...", ... }, ...]
eh.query("sp_items | count") { |row| ... } # streams rows, returns the count
```

### Lakehouse tables (SQL endpoint)

```ruby
db = MsFabric::Lakehouse::Database.new(
  sql_endpoint: "xxxx.datawarehouse.fabric.microsoft.com",
  database: "atlas_lake",
  **sp)

db.query("SELECT TOP 10 name, web_url FROM sp_items")   # => [{ "name" => ..., ... }]
db.close   # release the ODBC connection when done
```

### Lakehouse files (OneLake)

```ruby
files = MsFabric::Lakehouse::Files.new(
  workspace: "ATLAS-dev",
  lakehouse: "atlas_lake",
  **sp)

files.list_files("raw/sharepoint/docs")                 # => [{ "name"=>..., "size"=>..., ... }]
bytes = files.read_file("raw/sharepoint/docs/123__a.pdf")
files.read_file("big.zip") { |chunk| io.write(chunk) }  # streamed, returns nil
```

## Return shapes

- **Queries** return `Array<Hash>` with string keys; pass a block to stream rows instead of
  materializing them (returns the row count).
- **`read_file`** returns bytes, or streams chunks to a block.
- **`list_files`** returns `Array<Hash>`: `name`, `size`, `last_modified`, `is_directory`.

Nothing is silently capped — apply your own limits where results feed a bounded context.

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT
