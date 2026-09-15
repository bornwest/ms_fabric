class MsFabric
  class Error < StandardError; end
  class AuthError < Error; end             # token acquisition failed
  class ConnectionError < Error; end       # host unreachable / socket / TLS failure
  class TimeoutError < ConnectionError; end # open or read timed out
  class QueryError < Error; end            # server returned an error, or a read-only violation
  class ProtocolError < Error; end         # unexpected or unparseable response
end
