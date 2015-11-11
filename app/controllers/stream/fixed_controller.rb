class Stream::FixedController < StreamController
  def events
    # Rails reserve a db connection from connection pool for
    # each request, lets put it back into connection pool.
    ActiveRecord::Base.clear_active_connections!

    # Last time of any (except heartbeat) activity on stream
    # it mean last time of any message was send from server to client
    # or time of setting new connection
    @last_active = Time.zone.now

    # Redis (p)subscribe is blocking request so we need do some trick
    # to prevent it freeze request forever.
    redis.psubscribe("messages:*", 'heartbeat') do |on|
      on.pmessage do |pattern, event, data|
        # capture heartbeat from Redis pub/sub
        if event == 'heartbeat'
          # calculate idle time (in secounds) for this stream connection
          idle_time = (Time.zone.now - @last_active).to_i

          # Now we need to relase connection with Redis.(p)subscribe
          # chanel to allow go of any Exception (like connection closed)
          if idle_time > 4.minutes
            # unsubscribe from Redis because of idle time was to long
            # that's all - fix in (almost)one line :)
            redis.punsubscribe
          end
        else
          # save time of this (last) activity
          @last_active = Time.zone.now
        end
        # write to stream - even heartbeat - it's sometimes chance to
        # capture dissconection error before idle_time
        response.stream.write("event: #{event}\ndata: #{data}\n\n")
      end
    end
    # blicking end (no chance to get below this line without unsubscribe)
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
