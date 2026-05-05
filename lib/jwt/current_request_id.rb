class CurrentRequestId
  THREAD_KEY = :foaf_auth_request_id

  def self.value
    Thread.current[THREAD_KEY]
  end

  def self.with(value)
    previous = Thread.current[THREAD_KEY]
    Thread.current[THREAD_KEY] = value
    yield
  ensure
    Thread.current[THREAD_KEY] = previous
  end
end
