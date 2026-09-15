require_relative "lib/ms_fabric/version"

Gem::Specification.new do |spec|
  spec.name        = "ms_fabric"
  spec.version     = MsFabric::VERSION
  spec.authors     = ["Rishabh Gupta"]
  spec.email       = ["rishabh@bornwest.com"]

  spec.summary     = "Read-only Ruby client for Microsoft Fabric."
  spec.description  = "Connect to Microsoft Fabric services — Lakehouse tables (SQL endpoint) " \
                      "and files (OneLake), and Eventhouse (KQL) — with service-principal or " \
                      "managed-identity auth."
  spec.homepage    = "https://github.com/bornwest/ms_fabric"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # ruby-odbc is an OPTIONAL runtime dependency — only MsFabric::Lakehouse::Database (the SQL
  # endpoint) needs it, and it also requires the Microsoft ODBC Driver 18 (msodbcsql18) on the
  # host. Eventhouse and OneLake files use only the standard library. See the README.

  spec.add_development_dependency "rspec", "~> 3.13"
end
