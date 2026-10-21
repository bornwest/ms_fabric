require "spec_helper"

RSpec.describe MsFabric::Lakehouse::Files do
  subject(:files) do
    described_class.new(workspace: "ws", lakehouse: "lake", client_id: "c", client_secret: "s", tenant_id: "t")
  end

  let(:sent) { [] }
  let(:connection) { Object.new }

  before do
    allow_any_instance_of(MsFabric::Auth).to receive(:token).and_return("token")
    allow(MsFabric::Http).to receive(:session).and_yield(connection)
    allow(MsFabric::Http).to receive(:request) do |_uri, req, http:, **|
      raise "expected the shared connection" unless http.equal?(connection)

      sent << req
      FakeResponse.new("201", "", {})
    end
  end

  it "creates the file, appends it in chunks, and flushes at its length" do
    stub_const("MsFabric::Lakehouse::Files::CHUNK", 4)

    expect(files.write_file("dir/a b.pdf", "0123456789")).to eq(10)
    expect(sent.map { |r| [r.method, r.path.split("?").last, r.body] }).to eq(
      [["PUT", "resource=file", ""],
       ["PATCH", "action=append&position=0", "0123"],
       ["PATCH", "action=append&position=4", "4567"],
       ["PATCH", "action=append&position=8", "89"],
       ["PATCH", "action=flush&position=10", ""]],
    )
    expect(sent.first.path).to start_with("/ws/lake.Lakehouse/Files/dir/a%20b.pdf?")
    expect(sent.first["x-ms-version"]).to eq("2023-11-03")
  end

  it "reads from an IO and commits an empty file with a flush at 0" do
    expect(files.write_file("empty.csv", StringIO.new(""))).to eq(0)
    expect(sent.map(&:method)).to eq(%w[PUT PATCH])
    expect(sent.last.path).to end_with("action=flush&position=0")
  end

  it "raises QueryError when OneLake refuses the write" do
    allow(MsFabric::Http).to receive(:request).and_return(FakeResponse.new("403", "denied", {}))

    expect { files.write_file("a.pdf", "x") }.to raise_error(MsFabric::QueryError, /403/)
  end
end
