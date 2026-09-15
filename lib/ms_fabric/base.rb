class MsFabric
  # Base for every Fabric service client: holds credentials and hands out tokens. Subclasses
  # (Lakehouse::Database, Lakehouse::Files, Eventhouse::Database) own their transport.
  def initialize(client_id: nil, client_secret: nil, tenant_id: nil,
                 identity_endpoint: ENV["IDENTITY_ENDPOINT"], identity_header: ENV["IDENTITY_HEADER"])
    @client_id = client_id
    @client_secret = client_secret
    @auth = Auth.new(client_id:, client_secret:, tenant_id:, identity_endpoint:, identity_header:)
  end

  # ruby-odbc is an optional dependency — only Lakehouse::Database needs it.
  def self.load_odbc!
    @load_odbc ||= begin
      require "odbc"
      true
    rescue LoadError
      raise Error, "MsFabric::Lakehouse::Database needs the 'ruby-odbc' gem and the Microsoft " \
                   "ODBC Driver 18 (msodbcsql18). Add `gem \"ruby-odbc\", require: \"odbc\"` and " \
                   "install the driver."
    end
  end

  protected

  attr_reader :client_id, :client_secret

  def token(resource) = @auth.token(resource)

  def service_principal? = @auth.service_principal?
end
