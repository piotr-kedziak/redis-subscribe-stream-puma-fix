class Stream::BuggyController < StreamController
  def events
    # Rails reserve a db connection from connection pool for
    # each request, lets put it back into connection pool.
    ActiveRecord::Base.clear_active_connections!

    # Redis (p)subscribe is blocking request so we need do some trick
    # to prevent it freeze request forever.
    redis.psubscribe("messages:*", "heartbeat") do |on|
      on.pmessage do |pattern, event, data|
        # write to stream - even heartbeat - it's sometimes chance to
        # capture dissconection error before idle_time
        response.stream.write("event: #{event}\ndata: #{data}\n\n")
      end
    end
  rescue IOError
    Logs::Stream.info "Stream closed"
  rescue ClientDisconnected
    Logs::Stream.info "ClientDisconnected"
  rescue ActionController::Live::ClientDisconnected
    Logs::Stream.info "Live::ClientDisconnected"
  ensure
    Logs::Stream.info "Stream ensure close"
    redis.quit
    response.stream.close
  end
end
