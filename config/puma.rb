# Set the environment in which the rack's app will run. The value must be a string.
# The default is "development".
rails_env = ENV["RAILS_ENV"] || "development"
environment rails_env

# Change to match your CPU core count
workers 2

# Min and Max threads per worker
threads 1, (rails_env == "production" ? 36 : 16)

app_dir = File.expand_path("../..", __FILE__)
shared_dir = "#{app_dir}/tmp"
logs_dir = "#{app_dir}/log"

# The directory to operate out of.
# The default is the current directory.
# directory '/u/apps/lolcat'

# Use an object or block as the rack application. This allows the
# config file to be the application itself.
#
# app do |env|
#   puts env
#   body = 'Hello, World!'
#   [200, { 'Content-Type' => 'text/plain', 'Content-Length' => body.length.to_s }, [body]]
# end

# Load "path" as a rackup file.
# The default is "config.ru".
# rackup '/u/apps/lolcat/config.ru'


# Daemonize the server into the background. Highly suggest that
# this be combined with "pidfile" and "stdout_redirect".
#
# The default is "false".
daemonize (rails_env == "development" ? false : true )
pidfile "#{shared_dir}/pids/puma.pid"
state_path "#{shared_dir}/pids/puma.state"

# Store the pid of the server in the file at "path".
# pidfile '/u/apps/lolcat/tmp/pids/puma.pid'

# Use "path" as the file to store the server info state. This is
# used by "pumactl" to query and control the server.
# state_path '/u/apps/lolcat/tmp/pids/puma.state'

# Redirect STDOUT and STDERR to files specified. The 3rd parameter
# ("append") specifies whether the output is appended, the default is
# "false".
#
# stdout_redirect '/u/apps/lolcat/log/stdout', '/u/apps/lolcat/log/stderr'
# stdout_redirect '/u/apps/lolcat/log/stdout', '/u/apps/lolcat/log/stderr', true
if rails_env == "production"
  stdout_redirect "#{logs_dir}/puma.stdout.log", "#{logs_dir}/puma.stderr.log", true
end

# Disable request logging.
# The default is "false".
# quiet

# Configure "min" to be the minimum number of threads to use to answer
# requests and "max" the maximum.
# The default is "0, 16".
# threads 0, 16

# Bind the server to "url". "tcp://", "unix://" and "ssl://" are the only
# accepted protocols.
# The default is "tcp://0.0.0.0:9292".
#
# bind 'tcp://0.0.0.0:9292'
if rails_env == "production"
  bind "unix://#{shared_dir}/sockets/puma.sock"
else
  bind "tcp://0.0.0.0:3000"
end
# bind 'unix:///var/run/puma.sock?umask=0111'
# bind 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert'

# Instead of "bind 'ssl://127.0.0.1:9292?key=path_to_key&cert=path_to_cert'" you
# can also use the "ssl_bind" option.
# ssl_bind '127.0.0.1', '9292', { key: path_to_key, cert: path_to_cert }

# Code to run before doing a restart. This code should
# close log files, database connections, etc.
# This can be called multiple times to add code each time.
#
# on_restart do
#   puts 'On restart...'
# end

# Command to use to restart puma. This should be just how to
# load puma itself (ie. 'ruby -Ilib bin/puma'), not the arguments
# to puma, as those are the same as the original process.
# restart_command '/u/app/lolcat/bin/restart_puma'

# === Cluster mode ===

# How many worker processes to run.
# The default is "0".
# workers 0

# Code to run when a worker boots to setup the process before booting
# the app.
# This can be called multiple times to add hooks.
# on_worker_boot do
#   puts 'On worker boot...'
# end
on_worker_boot do
  require "active_record"
  ActiveRecord::Base.connection.disconnect! rescue ActiveRecord::ConnectionNotEstablished
  ActiveRecord::Base.establish_connection(YAML.load_file("#{app_dir}/config/database.yml")[rails_env])

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

# Code to run when a worker boots to setup the process after booting
# the app.
# This can be called multiple times to add hooks.
#
# after_worker_boot do
#   puts 'After worker boot...'
# end

# Code to run when a worker shutdown.
# on_worker_shutdown do
#   puts 'On worker shutdown...'
# end

# Allow workers to reload bundler context when master process is issued
# a USR1 signal. This allows proper reloading of gems while the master
# is preserved across a phased-restart. (incompatible with preload_app)
# (off by default)
# prune_bundler

# Preload the application before starting the workers; this conflicts with
# phased restart feature. (off by default)
# preload_app!

# Additional text to display in process listing
# tag 'app name'

# Change the default timeout of workers
worker_timeout 60

# === Puma control rack application ===

# Start the puma control rack application on "url". This application can
# be communicated with to control the main server. Additionally, you can
# provide an authentication token, so all requests to the control server
# will need to include that token as a query parameter. This allows for
# simple authentication.
#
# Check out https://github.com/puma/puma/blob/master/lib/puma/app/status.rb
# to see what the app has available.
#
# activate_control_app "unix://#{shared_dir}/sockets/pumactl.sock"
# activate_control_app 'unix:///var/run/pumactl.sock', { auth_token: '12345' }
# activate_control_app 'unix:///var/run/pumactl.sock', { no_token: true }
activate_control_app
