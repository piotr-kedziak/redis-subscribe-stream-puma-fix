# redis-subscribe-stream-puma-fix
Sample app with fix for error with Redis.(p)subscribe blocking stream threads in puma server.

# First...
This is one of many great experience I have during making some real-time chat app.
I have choosed to do it in Rails 4 (with optional jump to Node.js fore some parts in future).

# ActionController::Live
Rails 4 give us chance to use ActionController::Live.
There are many great resources about it like:
* (#401 ActionController::Live)[http://railscasts.com/episodes/401-actioncontroller-live?view=comments]
* (Is it live?)[http://tenderlovemaking.com/2012/07/30/is-it-live.html]
* (API)[http://edgeapi.rubyonrails.org/classes/ActionController/Live.html]

# What is this?
You can say Rails ActionController::Live stream is permanent connection between client and server. Your server are sending data to browser (client) without any ajax hell. When client disconect from server theat should be killed (by exception).

## Puma
I have used Unicorn for many projects but this time I was forced to use (Puma)[http://puma.io].

## Redis
As mentioned in RailsCasts and other examples - (one of) the best way to do pub/sub stream for Rails 4 app is use (Redis Pub/Sub)[http://redis.io/topics/pubsub].
Great for now! :)

# Problem
I have noticed that my dev server (at DigitalOcean) or local Vargant Virtual Machine gets many "zombie" threads from Puma. No mather how many workers and threads I setup. There always only mater of time to freeze app.

# Some code
First let's start with general (abstract) Stream Controller. This class will be parent for our stream controllers (two).

app/controllers/stream_controller.rb
```ruby
class StreamController < ApplicationController
  include ActionController::Live
  include Headers::Credential
  include Headers::Stream

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token

  before_action :set_headers_stream
  before_action :add_allow_credentials_headers

  protected
    def redis
      @redis ||= Redis.new
    end
  # protected
end
```

Let's talk about concerns: I have used tho concerns that you can use in any of your app ;)

One of them (Headers::Stream) sets headers as *"text/event-stream"*
app/controllers/concerns/headers/stream.rb
```ruby
module Headers::Stream
  extend ActiveSupport::Concern

  protected
    def set_headers_stream
      response.headers["Content-Type"] = "text/event-stream"
    end
  # protected
end
```

## Client side js (coffee)
It's just simply EventSource listener for one of urls (buggy or fixed) to show you how to handle stream.
```coffee
$ ->
  console.log "initializing stream"
  # for buggy version use:
  url = 'http://localhost:3000/stream_buggy'
  # for fixed version use:
  # url = 'http://localhost:3000/stream_fixed'
  source = new EventSource(url)
  source.addEventListener "messages.create", (e) ->
    # .. your js code here ;)
    alert "message received!"
    console.log e
```

## First - stream controller (with bug)
In my first controller I will show you basic functionality with Redis Pub/Sub. And if you will run it in your machine / app you will see:
- App will run but stream threads will not die after client disconnection;
- sooner or later (rather sooner) your server will stop responding for new requests (you've reached puma [workers*threads] limit);
- one and only way you left will be kill puma (Ctrl+C when it isn't demonized). After that you will see in logs many lines like *"...Completed 401 Unauthorized in 17780ms"* - each line for one thread

```ruby
class Stream::BuggyController < StreamController
  def events
    # Rails reserve a db connection from connection pool for
    # each request, lets put it back into connection pool.
    ActiveRecord::Base.clear_active_connections!

    # Redis (p)subscribe is blocking request so we need do some trick
    # to prevent it freeze request forever.
    redis.psubscribe("messages:*") do |on|
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
```

## Try to find cause
I have found that Redis.subscribe and Redis.psubscribe methods are **blocking**

*Once the client enters the subscribed state it is not supposed to issue any other commands, except for additional SUBSCRIBE, PSUBSCRIBE, UNSUBSCRIBE and PUNSUBSCRIBE commands.*
http://redis.io/commands/subscribe

There is even some epic story about it:
(Live streaming threads not dying)[https://github.com/rails/rails/issues/10989]

## Why?
So if you are using Redis Pub/Sub actions in your stream - there never be fired any Exception that can kill your thread..... Rails+Redis way! :/

## Screw it, use Socket.io
There is always option to use Node.js with (Socket.io)[http://socket.io]. I love Node.js but sometimes there isn't good idea to write whole app with it. Offcourse you can write only part of app using Node.js.

BTW: I finally do Rails app with Socket.io app to handle chat and real time data transfer but maybe in some cases you'd like to use Rails and I hope my work will help you.

## Maybe fix it?
What is the main problem ?

# Fix it - step 1 - Heartbeat
I have found some fix using background thread called Heartbeat:
https://stackoverflow.com/questions/18970458/redis-actioncontrollerlive-threads-not-dying/19485363#19485363

config/puma.rb
```ruby
on_worker_boot do |index|
  puts "worker nb #{index.to_s} booting"
  create_heartbeat if index.to_i==0
end

def create_heartbeat
  puts 'creating heartbeat'
  $redis||=Redis.new
  heartbeat = Thread.new do
    ActiveRecord::Base.connection_pool.release_connection
    begin
      while true
        hash = { event: 'heartbeat', data: 'heartbeat' }
        $redis.publish('heartbeat', hash.to_json)
        sleep 10.seconds
      end
    ensure
      #no db connection anyway
    end
  end
end
```

and change line 9 in Stream::BuggyController from:
```ruby
redis.psubscribe("messages:*") do |on|
```
to:
```ruby
redis.psubscribe("messages:*", "heartbeat") do |on|
```

# I still have a problem...
Yes, there is still blocking call in Redis.(p)subscribe loop. So heartbeat does nothing but it is great idea as first step.

# Remember basics
(Someone)[http://redis.io/commands/subscribe] in first comments discus about timeout.

wait..!! Great idea! but there is no timeout params in Redis.psubscribe and Redis.subscribe... but I can create this by myself.

# Fixed controller with timeout
There is basic implementation of Stream Controller with simple timeout for not used stream connections.

I have used heartbeat to check if connection is still active (in Chat app we can check it by last activity like message sent).

The trick is to use redis.(p)unsubscribe inside redis.(p)subscribe block after selected time of inactivity in thread. This will exit blocking redis.(p)subscribe and allow server to kill thread and free resources. I have choosed max idle time as **4.minutes** but you can choose any other time for your app :)

```ruby
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
```

# What if client will still have opened page?
When client will still have opened page (with ex. chat tab in background) and server will kill connected (but not active) thread EventSource on client side will do auto-reconnet with server. There is (almost) no risk for client.

# Nginx
There is offcourse nginx there but this is not important for this project (jet!).

# Vagrant and bootstrap.sh
There is Vagrant basic config to help you run fast test server for this repositiory.
