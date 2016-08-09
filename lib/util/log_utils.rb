#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby
module Puppetstein
  module LogUtils

    def log_notice(message)
      puts message
      puts "============================================"
    end
  end
end
