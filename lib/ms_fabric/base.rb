class MsFabric
  # Base for every Fabric service client: holds credentials and hands out tokens. Subclasses
  # (Lakehouse::Database, Lakehouse::Files, Eventhouse::Database) own their transport.
  def initialize(client_id: nil, client_secret: nil, tenant_id: nil,
                 identity_endpoint: ENV["IDENTITY_ENDPOINT"], identity_header: ENV["IDENTITY_HEADER"])
    @client_id = client_id
    @client_secret = client_secret
    @auth = Auth.new(client_id:, client_secret:, tenant_id:, identity_endpoint:, identity_header:)
  end

  # ruby-odbc ships as a dependency, but its native extension is required lazily so the rest of the
  # gem still loads where unixODBC/msodbcsql18 aren't installed (Eventhouse and files need neither).
  def self.load_odbc!
    @load_odbc ||= begin
      require "odbc"
      true
    rescue LoadError
      raise Error, "MsFabric::Lakehouse::Database needs unixODBC and the Microsoft ODBC Driver 18 " \
                   "(msodbcsql18) installed on the host."
    end
  end

  protected

  attr_reader :client_id, :client_secret

  def token(resource) = @auth.token(resource)

  def service_principal? = @auth.service_principal?
end
