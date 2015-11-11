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
