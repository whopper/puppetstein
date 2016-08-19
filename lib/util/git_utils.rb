#! /Users/whopper/.rbenv/shims/ruby

require 'json'
#! /usr/env/ruby

require 'open-uri'
require_relative 'platform_utils.rb'
require_relative 'log_utils.rb'

module Puppetstein
  module GitUtils
    def clone_repo(project, git_fork, sha, tmpdir, depth=nil)
      if File.exists?("#{tmpdir}/#{project}")
        execute("rm -rf #{tmpdir}/#{project}")
      end

      args = Hash.new
      args[:path] = "#{tmpdir}/"
      args[:depth] = depth if depth

      g = Git.clone("git@github.com:#{git_fork}/#{project}.git", project, args)
      g.fetch
      g.checkout(sha)
      log_notice("cloned #{project}:#{sha} to #{tmpdir}/#{project}")
    end

    def get_ref_from_pull_request(project, pr_number)
      puts project
      puts pr_number
      res = JSON.parse(open("https://api.github.com/repos/puppetlabs/#{project}/pulls/#{pr_number}").read)
      "#{res['user']['login']}:#{res['head']['ref']}"
    end
  end
end
