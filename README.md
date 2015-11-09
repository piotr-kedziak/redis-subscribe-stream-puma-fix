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

# I still have a problem...
Yes, there is still blocking call in Redis.(p)subscribe loop.

# Nginx
There is offcourse nginx there but this is not important for this project (jet!).

# Vagrant and bootstrap.sh
There is Vagrant basic config to help you run fast test server for this repositiory.
