test_name "Install puppetserver from builds.puppetlabs.lan or nightlies"

step "Install puppetserver dev repo on master" do
  agents.each do |agent|
    on(agent, "echo 'hello world: 020'") do
      puts stdout
    end
  end
end

