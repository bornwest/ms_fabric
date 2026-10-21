require_relative "lib/ms_fabric/version"

Gem::Specification.new do |spec|
  spec.name        = "ms_fabric"
  spec.version     = MsFabric::VERSION
  spec.authors     = ["Rishabh Gupta"]
  spec.email       = ["rishabh@bornwest.com"]

  spec.summary     = "Ruby client for Microsoft Fabric."
  spec.description = <<~TEXT.split.join(" ")
    Connect to Microsoft Fabric services — read-only Lakehouse tables (SQL endpoint) and Eventhouse
    (KQL), OneLake files read and write, and notebook runs — with service-principal or
    managed-identity auth.
  TEXT
  spec.homepage    = "https://github.com/bornwest/ms_fabric"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Powers MsFabric::Lakehouse::Database (the SQL endpoint). Compiles against unixODBC at install
  # time and needs the Microsoft ODBC Driver 18 (msodbcsql18) on the host at connect time.
  spec.add_dependency "ruby-odbc"

  spec.add_development_dependency "rspec", "~> 3.13"
end
