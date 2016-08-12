#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require 'open-uri'
require_relative 'platform_utils.rb'
require_relative 'log_utils.rb'

module Puppetstein
  module GitUtils
    def clone_repo(project, git_fork, sha='master', tmpdir)
      if File.exists?("#{tmpdir}/#{project}")
        execute("rm -rf #{tmpdir}/#{project}")
      end

      g = Git.clone("git@github.com:#{git_fork}/#{project}.git", project, :path => "#{tmpdir}/")
      g.fetch
      g.checkout(sha)
      log_notice("cloned #{project}:#{sha} to #{tmpdir}/#{project}")
    end

    def get_ref_from_pull_request(project, pr_number)
      res = JSON.parse(open("https://api.github.com/repos/puppetlabs/#{project}/pulls/#{pr_number}").read)
      "#{res['user']['login']}:#{res['head']['ref']}"
    end
  end
end
