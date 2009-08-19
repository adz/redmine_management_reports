class ManagementReportsController < ApplicationController
  unloadable
  
  def index
    @project = Project.find(params[:project_id])

    # Run on Monday, to get previous Mon - Sunday
    @from = (params[:from] || Date.current - 7).to_date
    @to   = (params[:to]   || Date.current - 1).to_date
    @version = if params[:version]
      Version.find(params[:version].split(','))
    else
      @project.versions.reject(&:completed?)
    end

    new_issues = @project.issues.find(:all,
      :conditions => {
        :created_on => @from..(@to+1) # cheat -- +1 as time is from midnight
      }
    )
    @new_issues_report = new_issues_report(new_issues)


    @time_entries = TimeEntry.all(:conditions => {
        :spent_on => (@from..@to)
      }
    )
    @time_entries_report = time_entries_report(@time_entries)



    @remaining_issues = @project.issues.find(:all,
      :conditions => {
        :status_id => IssueStatus.all(:conditions => {:is_closed => false}),
        :fixed_version_id => @version
      }
    )
    @remaining_issues_report = remaining_issues_report(@remaining_issues)

    @active_versions = @project.versions.reject(&:completed?)

    respond_to do |format|
      format.csv do
        csv_text = "*Quicktravel Management Reports*

New Issues
#{Munger::Render.to_csv(@new_issues_report)}

Time Entries
#{Munger::Render.to_csv(@time_entries_report)}

Remaining Issue
#{Munger::Render.to_csv(@remaining_issues_report)}
        "
        render :text => csv_text, :mime_type => "text/csv"
      end
      format.html {}
    end
  end

  private
  def new_issues_report(new_issues)
    data = Munger::Data.load_data(new_issues.map{|issue|
        issue.attributes.merge(
          :status   => issue.status.to_s,
          :project  => issue.project.to_s,
          :tracker  => issue.tracker.to_s,
          :priority => issue.priority.to_s
        )
      }
    )
    data.transform_column(:estimated_hours) do |row|
      row.estimated_hours || 0
    end

    new_issues_report = Munger::Report.from_data(data).process
    new_issues_report.columns [:id, :status, :project, :tracker, :priority, :subject, :estimated_hours]
    new_issues_report.aggregate(:sum => :estimated_hours).process
    humanize_column_titles(new_issues_report)

    new_issues_report.style_rows('issue') {|row| true} # always styles rows as issues

    new_issues_report
  end


  def time_entries_report(time_entries)
    # Get data
    time_entry_data = Munger::Data.load_data(time_entries.map{|time_entry|
        {
          :project  => "#{time_entry.project}",
          :activity => "#{time_entry.activity}",
          :created  => time_entry.created_on.to_date,
          :hours    => time_entry.hours,
          :issue    => "#{time_entry.issue}",
          :comments => time_entry.comments
        }
      }
    )

    # Build report
    time_entry_report = Munger::Report.from_data(time_entry_data)
    time_entry_report.columns [:project, :activity, :created, :hours, :issue, :comments]

    humanize_column_titles(time_entry_report)

    time_entry_report.process

    time_entry_report.style_rows('issue'){|row|true}
    time_entry_report.aggregate(:sum => :hours).process

    time_entry_report.sort([:project, :activity])
    time_entry_report.subgroup([:project, :activity], :with_headers => true)

    # Return it
    time_entry_report.process
  end


  def remaining_issues_report(remaining_issues)
    data = Munger::Data.load_data(remaining_issues.map{|issue|
        issue.attributes.merge(
          :status   => issue.status.to_s,
          :project  => issue.project.to_s,
          :tracker  => issue.tracker.to_s,
          :priority => issue.priority.to_s
        )
      }
    )

    data.transform_column(:estimated_hours) do |row|
      row.estimated_hours || 'No Est'
    end

    data.add_column(:time_spent) do |row|
      puts row.inspect
      TimeEntry.all(:conditions => {:issue_id => row.id}).map(&:hours).sum
    end

    data.transform_column(:done_ratio) do |row|
      "#{row.done_ratio}%"
    end


    new_issues_report = Munger::Report.from_data(data).process
    new_issues_report.columns [:id, :tracker, :priority, :subject, :estimated_hours, :done_ratio, :time_spent]
    humanize_column_titles(new_issues_report)

    new_issues_report.style_rows('issue') {|row| true} # always styles rows as issues

    new_issues_report
  end


  def humanize_column_titles(report)
    report.column_titles = report.
      columns.
      map{|col| {col => col.to_s.humanize} }.
      inject({}) {|a,b| a.merge(b) }
  end
end
