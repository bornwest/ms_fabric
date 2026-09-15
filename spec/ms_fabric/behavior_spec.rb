require "spec_helper"

RSpec.describe "error taxonomy" do
  it "nests connection/timeout and keeps everything under MsFabric::Error" do
    expect(MsFabric::TimeoutError.ancestors).to include(MsFabric::ConnectionError, MsFabric::Error)
    expect(MsFabric::AuthError.ancestors).to include(MsFabric::Error)
    expect(MsFabric::QueryError.ancestors).to include(MsFabric::Error)
    expect(MsFabric::ProtocolError.ancestors).to include(MsFabric::Error)
  end
end

RSpec.describe MsFabric::Http do
  Res = Struct.new(:body, :code)

  it "parses JSON responses" do
    expect(described_class.json(Res.new('{"a":1}', "200"))).to eq("a" => 1)
  end

  it "raises ProtocolError on a non-JSON body" do
    expect { described_class.json(Res.new("<html>gateway error</html>", "502")) }
      .to raise_error(MsFabric::ProtocolError, /expected JSON/)
  end
end

RSpec.describe "read-only guards" do
  let(:sp) { { client_id: "c", client_secret: "s", tenant_id: "t" } }

  it "Lakehouse::Database rejects non-SELECT before touching the network" do
    db = MsFabric::Lakehouse::Database.new(sql_endpoint: "x", database: "d", **sp)
    expect { db.query("DELETE FROM t") }.to raise_error(MsFabric::QueryError, /read-only/)
  end

  it "Eventhouse::Database rejects control commands before touching the network" do
    eh = MsFabric::Eventhouse::Database.new(cluster_uri: "https://x", database: "d", **sp)
    expect { eh.query(".drop table t") }.to raise_error(MsFabric::QueryError, /read-only/)
  end
end
