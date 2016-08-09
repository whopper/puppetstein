#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'log_utils.rb'

module Puppetstein
  module GitUtils

    def clone_repo(project, git_fork, sha='master')
      if !File.exists?("/tmp/#{project}")
        g = Git.clone("git@github.com:#{git_fork}/#{project}.git", project, :path => '/tmp/')
        g.branch(sha).checkout
        log_notice("cloned #{project}#{sha} to /tmp/#{project}")
      else
        g = Git.open("/tmp/#{project}")

        remote_exists = false
        g.remotes.each do |remote|
          remote_exists = true if remote.name == git_fork
        end

        g.add_remote(git_fork, "git@github.com:#{git_fork}/#{project}.git") unless remote_exists
        g.remote(git_fork).fetch
        g.branch(sha).checkout
        log_notice("Found local checkout of #{project} in /tmp/#{project}. Using #{git_fork}:#{sha}")
      end
    end
  end
end
