require 'test/unit'
require_relative 'utils/mock_server.rb'

# start coverage
require "simplecov"
SimpleCov.start

# use config test
ENV["UPDATEREPOS"] = "test/test_update_gitrepos.yml"
require_relative '../update_gitrepos.rb'

$envpath = '/tmp/update_gitrepo_test_env'

# start mock server
$server = MockServer.new
server_thread = Thread.new do
    $server.run
end
server_thread.abort_on_exception = true

class UpdateGitReposTest < Test::Unit::TestCase

    def setup
        $server.add_response(Response.new)
        puts "Test env dir created" if system("mkdir -p #{$envpath}")
        Dir.chdir $envpath
        puts "Git repo initialized in test env" if system("git init")
        puts "Origin added" if system("git remote add origin http://localhost:4567")
        system("git checkout -b master")
    end

    def teardown
        puts "Cleaned env dir" if system("rm -rf #{$envpath}")
    end

    def test_actual_branch
        assert_equal("master", GitCommands.new.get_actual_branch)
    end

    def test_fetch
        $server.add_response(Response.new)
        assert_equal(true, GitCommands.new.fetch_repo)
    end

    def test_change_branch
        system("git checkout -b test")
        system("touch a")
        system("git add a")
        system("git commit -m test")
        system("git checkout -b test2")
        assert_equal("test2", GitCommands.new.get_actual_branch)
        assert_equal(true, GitCommands.new.change_to_branch("test"))
        assert_equal("test", GitCommands.new.get_actual_branch)
    end

    def test_is_branch_dirty
        assert_equal(false, GitCommands.new.is_actual_branch_dirty?)
        system("touch a")
        assert_equal(true, GitCommands.new.is_actual_branch_dirty?)
    end

end
