require "spec_helper"

RSpec.describe MsFabric::Workspace do
  subject(:workspace) { described_class.new(name: "ATLAS", client_id: "c", client_secret: "s", tenant_id: "t") }

  let(:listings) do
    { "/v1/workspaces" => [{ "id" => "w1", "displayName" => "ATLAS" }],
      "/v1/workspaces/w1/notebooks" => [{ "id" => "n1", "displayName" => "nb_parse_manual" }],
      "/v1/workspaces/w1/lakehouses" => [{ "id" => "l1", "displayName" => "atlas_lake" }],
      "/v1/workspaces/w1/sqlEndpoints" => [{ "id" => "s1", "displayName" => "atlas_lake" }] }
  end

  before do
    allow_any_instance_of(MsFabric::Auth).to receive(:token).and_return("token")
    allow(workspace).to receive(:sleep)
    allow(MsFabric::Http).to receive(:request) do |uri, _req, **|
      FakeResponse.new("200", JSON.generate("value" => listings.fetch(uri.path)), {})
    end
  end

  it "starts a notebook run with typed parameters and the default lakehouse, without retrying" do
    started = nil
    allow(MsFabric::Http).to receive(:perform) do |_uri, req, _timeout|
      started = req
      FakeResponse.new("202", "", { "Location" => "https://api/jobs/9" })
    end

    job = workspace.run_notebook("nb_parse_manual", parameters: { MAX_FILES: 5, FLAG: true, NAME: "x" },
                                                    lakehouse: "atlas_lake")

    expect(job).to eq("https://api/jobs/9")
    expect(started.path).to eq("/v1/workspaces/w1/items/n1/jobs/instances?jobType=RunNotebook")
    execution = JSON.parse(started.body)["executionData"]
    expect(execution["parameters"]).to eq(
      "_inlineInstallationEnabled" => { "value" => "True", "type" => "bool" },
      "MAX_FILES" => { "value" => "5", "type" => "int" },
      "FLAG" => { "value" => "True", "type" => "bool" },
      "NAME" => { "value" => "x", "type" => "string" },
    )
    expect(execution.dig("configuration", "defaultLakehouse"))
      .to eq("name" => "atlas_lake", "workspaceId" => "w1", "id" => "l1")
  end

  it "waits for a job to finish" do
    states = %w[NotStarted InProgress Completed]
    allow(MsFabric::Http).to receive(:request) { FakeResponse.new("200", JSON.generate("status" => states.shift), {}) }

    expect(workspace.wait("https://api/jobs/9", every: 0)["status"]).to eq("Completed")
  end

  it "polls a SQL endpoint refresh until it succeeds" do
    allow(MsFabric::Http).to receive(:request) do |uri, req, **|
      case [req.method, uri.path]
      in ["POST", "/v1/workspaces/w1/sqlEndpoints/s1/refreshMetadata"]
        FakeResponse.new("202", "", { "Location" => "https://api/operations/7", "Retry-After" => "1" })
      in ["GET", "/operations/7"] then FakeResponse.new("200", JSON.generate("status" => "Succeeded"), {})
      in ["GET", path] then FakeResponse.new("200", JSON.generate("value" => listings.fetch(path)), {})
      end
    end

    expect(workspace.refresh_sql_endpoint("atlas_lake")).to be_nil
  end

  it "names a missing notebook" do
    expect { workspace.run_notebook("nb_nope") }.to raise_error(MsFabric::QueryError, /no notebooks item named nb_nope/)
  end
end
