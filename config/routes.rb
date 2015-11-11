Rails.application.routes.draw do
  get 'stream_buggy', controller: 'stream/buggy', action: :events
  get 'stream_fixed', controller: 'stream/fixed', action: :events
end
