#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'log_utils.rb'

module Puppetstein
  module GitUtils

    def clone_repo(project, sha='master')
      if !File.exists?("/tmp/#{project}")
        g = Git.clone("git@github.com:puppetlabs/#{project}.git", project, :path => '/tmp/')
        g.branch(sha).checkout
        log_notice("cloned #{project}#{sha} to /tmp/#{project}")
      else
        g = Git.open("/tmp/#{project}")
        g.branch(sha).checkout
        log_notice("Found local checkout of #{project} in /tmp/#{project}. Using #{sha}")
      end
    end
  end
end
