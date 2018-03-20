#!/usr/bin/env ruby
#
# UPDATE GIT REPOS AUTOMATICALLY
#
# Usage:
#   - Call this script from your shell configuration file, p.ex add the following line:
#       $HOME/.dotfiles/update_gitrepos.rb
#   - Use config file (.gitrepouptade.yml) to enumerate the repos to update
#
# Configuration properties:
#   - modules:  default:: empty
#               The list of git modules to check for updates.
#               Each module needs properties <path> with the local path of the repo and the <branch>
#               with the branch name to update.
#
#   - log-level:    default:: "info"
#                   The level of the logger, it corresponds with Logger::Severity ruby class levels.
#
#   - last-update-file: default:: "/tmp/gitreposupdated"
#                       The file where the last time update is stored.
#
#   - global-time-update:   default:: true
#                           Activates a single time stored in file.
#                           Last time update can be singly stored for each repo, if you have a lot of
#                           configured repos that could increase the session startup. In this case
#                           activate this feature to use a global time and increase the efficiency.
#                           Note: Activating it the new added repos won't be detected since a day will end.

require "yaml"
require "logger"

$logger = Logger.new(STDOUT)
$last_update_file = nil
$global_time_update = true

# Git command helper
class GitCommands

    # Returns <true> if there are some not stashed changes in the actual branch of the actual repo.
    def is_actual_branch_dirty?
        !(`git status --short`.empty?)
    end

    # Returns the actual branch of the actual repo.
    def get_actual_branch
        `git symbolic-ref --quiet HEAD`.split("/")[2].strip!
    end

    # Changes of the given branch the actual repo.
    # Params:
    # +branch+:: the branch where move to.
    def change_to_branch branch
        system("git checkout #{branch} --quiet > /dev/null 2>&1")
    end

    # Fetches the actual repo with remote called <origin>
    def fetch_repo
        system("git fetch origin > /dev/null 2>&1")
    end
end

# Simple manager to check if the repo is up to date
class GitRepoManager

    def initialize
        @git_commands = GitCommands.new
    end

    # Checks if a given repo in a given path needs to be updated and ask to user for it.
    # Params:
    # +repo_path+:: path of the git repository to check
    # +branch+:: branch name to check
    def check_for_updates(repo_path, branch)
        $logger.debug "Checking #{repo_path} for updates..."
        actual_location = Dir.pwd
        Dir.chdir repo_path

        actual_branch = @git_commands.get_actual_branch
        local_branch = branch
        remote_branch = 'origin/' << branch

        if @git_commands.is_actual_branch_dirty?
            $logger.info "There are not stashed changes in branch #{actual_branch}"
            $logger.info "...Aborting update"
            return
        end

        # move to branch and fetch remote
        @git_commands.change_to_branch local_branch
        @git_commands.fetch_repo

        if not is_up_to_date?(remote_branch, local_branch)
            puts "#{repo_path} needs updates to sync remote:"
            puts "Do you want to update? How: merge [m], rebase [r], reset hard [R], abort [a/A]"
            res = gets.chomp
            if not res.nil?
                case res
                when "m" 
                    error = `git merge #{remote_branch}`
                when "r"
                    error = `git rebase #{remote_branch}`
                when "R"
                    puts "This will delete local changes, are you sure to continue? [N,y]"
                    res = gets.chomp.downcase
                    if not res.nil? and ["yes","y"].include? res
                        error = `git reset --hard #{remote_branch}`
                    end
                when /a|A/
                    $logger.info "...Aborting update"
                end
            end
            $logger.error ">>> " << error unless error.nil?
        else
            $logger.debug "...Already up to date"
        end

        # return to orginal state
        @git_commands.change_to_branch actual_branch
        Dir.chdir actual_location
    end

    private

    # Returns the last commit hash of a given branch
    # Params:
    # +branch+:: branch name
    def get_last_commit_hash(branch)
        output = `git log -1 #{branch}`
        output.split(' ').first
    end

    # Checks if two branches are in the same commit
    # Params:
    # +remote_branch+:: remote branch name
    # +local_branch+:: local branch name
    def is_up_to_date?(remote_branch, local_branch)
        remote_commit = get_last_commit_hash(remote_branch) 
        local_commit = get_last_commit_hash(local_branch)
        $logger.debug "\tremote commit: #{remote_commit} [#{remote_branch}]\n\tlocal commit: #{local_commit} [#{local_branch}]"
        return remote_commit.eql? local_commit
    end
end

# Simple manager to store the last update check
class TimeManager

    # Returns <true> if its time to check for updates again
    # Params:
    # +repo_path+:: the path of the repo that has to check
    def will_check_for_updates? repo_path
        if $last_update_file.nil? or $last_update_file.empty?
            $last_update_file = "/tmp/gitreposupdated"
        end
        last_update = nil

        if File.exist? $last_update_file
            last_update = read_time($last_update_file, repo_path)
        end

        if last_update.nil? or Time.now.to_i - last_update > 24 * 60 * 60
            write_time($last_update_file, repo_path)
            return true
        end
        return false
    end

    private

    # Saves the last time when git repos were checked for updates.
    # The times are classified by the repo path.
    # Params:
    # +file+:: file name where store the time
    # +repo_path+:: the path of the given repo
    def write_time(file, repo_path)
        File.delete(file) if File.exist? file
        file = File.new(file,"a")
        file.puts($global_time_update ? Time.now.to_i : "#{repo_path}:#{Time.now.to_i}")
        file.close
    end

    # Loads the last time when git repos were checked for updates.
    # Search for the given repo
    # Params:
    # +file+:: file name where load the time
    # +repo_path+:: the path of the given repo to read
    def read_time(file, repo_path)
        File.open(file,"r") do |f|
            f.each_line do |line|
                if $global_time_update
                    f.close
                    return line.to_i
                else
                    splitted = line.split ":"
                    if splitted[0].eql? repo_path
                        f.close
                        return splitted[1].to_i
                    end
                end
            end
        end
        return nil
    end
end

# Simple manager to load the config file
# Atributtes:
# +modules+:: list of modules to check (each one contains path and branch)
class ConfigManager
    attr_accessor :modules
    attr_accessor :enabled

    def initialize
        conf = YAML.load_file(ENV["UPDATEREPOS"].empty? ? ENV["HOME"]+"/.gitrepoupdate.yml" : ENV["UPDATEREPOS"])
        @modules = conf["modules"]
        @enabled = conf["enabled"]

        #last updated file
        $last_update_file = conf["last-update-file"]
        $global_time_update = conf["global-time-update"]
        #logger
        $logger.formatter = proc do |serverity, time, progname, msg|
            "#{msg}\n"
        end
        $logger.level = case conf["log-level"]
                        when "info"
                            Logger::INFO
                        when "debug"
                            Logger::DEBUG
                        when "warn"
                            Logger::WARN
                        when "error"
                            Logger::ERROR
                        when "fatal"
                            Logger::FATAL
                        else
                            Logger::INFO
                        end
    end
end

# Main execution of the script
def main
    gitrepo_manager = GitRepoManager.new
    timeMgr = TimeManager.new
    if timeMgr.will_check_for_updates? nil
        config = ConfigManager.new
        if config.enabled
            config.modules.each do |gitmodule|
                if $global_time_update or timeMgr.will_check_for_updates? gitmodule["path"]
                    gitrepo_manager.check_for_updates gitmodule["path"], gitmodule["branch"]
                end
            end
        end
    end
end

# execute it
main
