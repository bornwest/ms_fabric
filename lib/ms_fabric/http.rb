class MsFabric
  # Shared HTTP: timeouts, network-fault wrapping, transient-status retry, and JSON parsing.
  # GETs and the query POSTs are idempotent (read-only), so retrying them is safe.
  module Http
    OPEN_TIMEOUT = 15
    DEFAULT_READ_TIMEOUT = 100
    MAX_RETRIES = 3
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
    NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError,
                      SystemCallError, OpenSSL::SSL::SSLError].freeze

    module_function

    # Returns the response; retries transient statuses/network faults with backoff.
    def request(uri, req, read_timeout: DEFAULT_READ_TIMEOUT)
      attempt = 0
      loop do
        attempt += 1
        begin
          res = perform(uri, req, read_timeout)
        rescue ConnectionError
          raise if attempt > MAX_RETRIES
          sleep(backoff(attempt)); next
        end
        return res unless RETRY_STATUSES.include?(res.code.to_i) && attempt <= MAX_RETRIES

        sleep(retry_after(res, attempt))
      end
    end

    # Streams the response to the block (nothing buffered); wraps network faults.
    def stream(uri, req, read_timeout: DEFAULT_READ_TIMEOUT)
      start(uri, read_timeout) { |http| http.request(req) { |res| yield res } }
    rescue *NETWORK_ERRORS => e
      raise wrap(uri, e)
    end

    def json(res)
      JSON.parse(res.body)
    rescue JSON::ParserError
      raise ProtocolError, "expected JSON but got (HTTP #{res.code}): #{res.body.to_s[0, 200]}"
    end

    def perform(uri, req, read_timeout)
      start(uri, read_timeout) { |http| http.request(req) }
    rescue *NETWORK_ERRORS => e
      raise wrap(uri, e)
    end

    def start(uri, read_timeout, &block)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout:, &block)
    end

    def wrap(uri, err)
      if err.is_a?(Net::OpenTimeout) || err.is_a?(Net::ReadTimeout)
        TimeoutError.new("request to #{uri.host} timed out: #{err.message}")
      else
        ConnectionError.new("could not reach #{uri.host}: #{err.message}")
      end
    end

    def backoff(attempt) = (2**attempt) * 0.3

    def retry_after(res, attempt) = (res["Retry-After"] || backoff(attempt)).to_f
  end
end
