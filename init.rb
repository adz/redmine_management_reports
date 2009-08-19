require 'redmine'

# Use munger
gem 'munger'
require 'munger'

#require "/home/adam/projects/munger/adz/lib/munger" #File.expand_path(File.dirname(__FILE__) + "/../lib/munger")


Redmine::Plugin.register :redmine_management_reporting do
  name 'Redmine Management Reporting plugin'
  author 'Adam Davies'
  description 'Show time-logged and issue progress for management reporting'
  version '0.0.1'

  permission :management_reports, {:management_reports => [:index]}, :public => true
  menu :project_menu, :management_reports, {:controller => 'management_reports', :action => 'index'}, :caption => 'Management Reports', :after => :activity, :param => :project_id

end
