require "spec_helper"

RSpec.describe MsFabric::Auth do
  it "uses the service-principal flow when client credentials are given" do
    auth = described_class.new(client_id: "cid", client_secret: "sec", tenant_id: "tid")
    expect(auth.service_principal?).to be(true)
  end

  it "falls back to managed identity when no client credentials are given" do
    auth = described_class.new(identity_endpoint: "http://localhost/msi")
    expect(auth.service_principal?).to be(false)
  end

  it "raises when neither credentials nor an identity endpoint are available" do
    auth = described_class.new
    allow(ENV).to receive(:[]).with("IDENTITY_ENDPOINT").and_return(nil)
    allow(ENV).to receive(:[]).with("IDENTITY_HEADER").and_return(nil)
    expect { auth.token("https://vault.azure.net") }.to raise_error(MsFabric::AuthError, /no credentials/)
  end
end
