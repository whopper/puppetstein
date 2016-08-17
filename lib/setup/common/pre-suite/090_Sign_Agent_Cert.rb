test_name "Sign agent cert on master"

step "Configure agent to use master in puppet.conf" do
  agents.each do |agent|
    on(agent, "echo 'hello world: 090 common'") do
      puts stdout
    end
  end
end

