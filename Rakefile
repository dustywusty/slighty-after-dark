require 'rubygems'


# Bootstrap
#-----------------------------------------------------------------------------#

desc "initializes your working copy"
task :bootstrap do
  title "updating submodules"
  execute_command "git submodule update --init --recursive"

  title "installing gems"
  execute_command "bundle install"
end

# Build
#-----------------------------------------------------------------------------#

desc "build slightly-after-dark"
task :build do
  title "Building"

  require 'xcoder'

  config = Xcode.project('slightly-after-dark').target('slightly-after-dark').config(:Debug)
  builder = config.builder
  builder.clean
  builder.build :sdk => :macosx

end

# Helpers
#-----------------------------------------------------------------------------#

def execute_command(command)
  if ENV['VERBOSE']
    sh(command)
  else
    output = `#{command} 2>&1`
    raise output unless $?.success?
  end
end

def title(title)
  cyan_title = "\033[0;36m#{title}\033[0m"
  puts
  puts "-" * 80
  puts cyan_title
  puts "-" * 80
  puts
end
