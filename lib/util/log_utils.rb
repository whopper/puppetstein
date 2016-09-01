#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby
module Puppetstein
  module LogUtils
    def log_notice(message)
      puts message
      puts "============================================"
    end

    # Returns YAML object containing all host info of last run
    def get_latest_host_config
      log = YAML.load_file('log/latest/hosts_preserved.yml')
      log.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    end
  end
end
