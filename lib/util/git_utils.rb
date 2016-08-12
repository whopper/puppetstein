#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'platform_utils.rb'
require_relative 'log_utils.rb'

module Puppetstein
  module GitUtils

    def clone_repo(project, git_fork, sha='master')
      if File.exists?("/tmp/#{project}")
        execute("rm -rf /tmp/#{project}")
      end

      g = Git.clone("git@github.com:#{git_fork}/#{project}.git", project, :path => '/tmp/')
      g.branch(sha).checkout
      log_notice("cloned #{project}:#{sha} to /tmp/#{project}")
    end
  end
end
