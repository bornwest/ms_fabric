class MsFabric
  # The Fabric REST API for one workspace, by display name: run notebooks and follow their jobs,
  # and refresh a lakehouse's SQL analytics endpoint.
  class Workspace < MsFabric
    API = "https://api.fabric.microsoft.com".freeze
    FINISHED = %w[Completed Failed Cancelled Deduped].freeze

    def initialize(name:, **auth)
      super(**auth)
      @name = name
    end

    # Starts a run of `notebook` and returns its job URL, for job_status and wait. `parameters` set
    # its parameters-cell variables; `lakehouse` binds the default lakehouse, which a run started
    # through the API otherwise lacks. Inline %pip installs are enabled, as the API refuses them by
    # default. Not retried: a repeated start would be a second run.
    def run_notebook(notebook, parameters: {}, lakehouse: nil)
      execution = { parameters: { _inlineInstallationEnabled: { value: "True", type: "bool" },
                                  **parameters.to_h { |k, v| [k, typed(v)] } } }
      if lakehouse
        execution[:configuration] = { defaultLakehouse: { name: lakehouse, workspaceId: id,
                                                          id: item("lakehouses", lakehouse)["id"] } }
      end
      path = "/workspaces/#{id}/items/#{item("notebooks", notebook)["id"]}/jobs/instances?jobType=RunNotebook"
      res = Http.perform(uri(path), request(:Post, path, executionData: execution), Http::DEFAULT_READ_TIMEOUT)
      ok!(res)["Location"]
    end

    # The job's state: { "status" => "NotStarted" | "InProgress" | "Completed" | "Failed" | …,
    # "failureReason" => { "message" => … } }.
    def job_status(job) = Http.json(call(:Get, job))

    # Polls the job every `every` seconds until it finishes; returns its final state.
    def wait(job, every: 30, timeout: 3600)
      deadline = Time.now + timeout
      loop do
        state = job_status(job)
        return state if FINISHED.include?(state["status"])
        raise TimeoutError, "job still #{state["status"]} after #{timeout}s" if Time.now > deadline

        sleep every
      end
    end

    # Syncs the lakehouse's SQL analytics endpoint with its Delta tables now, so new tables and rows
    # are queryable without waiting for Fabric's background sync.
    def refresh_sql_endpoint(lakehouse)
      endpoint = item("sqlEndpoints", lakehouse)
      await(call(:Post, "/workspaces/#{id}/sqlEndpoints/#{endpoint["id"]}/refreshMetadata", {}))
      nil
    end

    private

    def id
      @id ||= list("/workspaces").find { |w| w["displayName"] == @name }&.fetch("id") ||
              raise(QueryError, "workspace #{@name} not found or not visible")
    end

    def item(kind, name)
      list("/workspaces/#{id}/#{kind}").find { |i| i["displayName"] == name } ||
        raise(QueryError, "no #{kind} item named #{name} in #{@name}")
    end

    # Every page of a list endpoint.
    def list(path)
      items, url = [], path
      while url
        body = Http.json(call(:Get, url))
        items.concat(body.fetch("value", []))
        url = body["continuationUri"]
      end
      items
    end

    # Long-running operations answer 202 with a Location to poll until Succeeded.
    def await(res)
      while res.code == "202"
        sleep res["Retry-After"].to_i.clamp(1, 10)
        res = call(:Get, res["Location"])
        state = Http.json(res)["status"]
        raise QueryError, "operation #{state}: #{res.body.to_s[0, 300]}" if %w[Failed Cancelled].include?(state)
        break if state == "Succeeded"
      end
      res
    end

    def call(method, path, body = nil)
      ok!(Http.request(uri(path), request(method, path, body)))
    end

    def request(method, path, body = nil)
      Net::HTTP.const_get(method).new(uri(path)).tap do |req|
        req["Authorization"] = "Bearer #{token(API)}"
        req["Content-Type"] = "application/json"
        req.body = body.nil? ? "" : JSON.generate(body)
      end
    end

    def uri(path) = URI(path.start_with?("http") ? path : "#{API}/v1#{path}")

    def ok!(res)
      return res if res.code.to_i.between?(200, 299)

      raise QueryError, "Fabric #{res.code}: #{res.body.to_s[0, 300]}"
    end

    # 3 -> int, true -> bool ("True"), anything else -> string: the types a parameters cell takes.
    def typed(value)
      case value
      when Integer then { value: value.to_s, type: "int" }
      when true, false then { value: value.to_s.capitalize, type: "bool" }
      else { value: value.to_s, type: "string" }
      end
    end
  end
end
