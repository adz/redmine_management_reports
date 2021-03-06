class ManagementReportsController < ApplicationController
  unloadable


  #
  # All issues created in period (new)
  # All issues with time-entries for period
  # All remaining issues (not completed)
  #
  # Merge the lot
  #
  # Include time-spent in total
  # Include time-spent in period
  #
  def index
    @project = Project.find(params[:project_id])

    # Run on Monday, to get previous Mon - Sunday
    @from = (params[:from] || Date.current - 7).to_date
    @to   = (params[:to]   || Date.current - 1).to_date
    @versions = if (!params[:versions].blank? and !params[:versions].reject(&:blank?).empty? )
      Version.find_all_by_id(params[:versions])
    else
      @project.versions.reject(&:completed?)
    end

    # All issues created in period (new)
    # All issues with time-entries for period
    # All remaining issues (not completed)
    #
    # Merge the lot
    @reportable_issues = get_reportable_issues(@project, @versions, @from, @to)

    data = Munger::Data.load_data(@reportable_issues)
    data.transform_column(:estimated_hours) do |row|
      row.estimated_hours || 0.0
    end

    @reportable_issues_report = Munger::Report.from_data(data).process
    @reportable_issues_report.columns [:id, :why, :status, :project, :tracker, :priority, :subject, :estimated_hours, :time_spent_to_date, :time_spent_in_period, :remaining]
    @reportable_issues_report.sort(:id).aggregate(:sum => [:estimated_hours, :time_spent_in_period, :remaining]).process
    humanize_column_titles(@reportable_issues_report)

    @reportable_issues_report.style_rows('issue') {|row| true} # always styles rows as issues
    @reportable_issues_report.style_rows('completedIssue') {|row| row[:status] && %w(Closed Resolved).include?(row[:status]) } # always styles rows as issues

    @reportable_issues_report.style_cells('numeric') {|cell,row| cell.is_a?(Numeric)}

    @active_versions = @project.versions.reject(&:completed?)

    respond_to do |format|
      format.csv do
        csv_text = "*Quicktravel Management Reports*

All Work: Done & Remaining
#{Munger::Render.to_csv(@reportable_issues_report)}
"
        render :text => csv_text, :mime_type => "text/csv"
      end
      format.html {}
    end
  end

  private
  def get_reportable_issues(project, versions, from, to)
    new_issues = project.issues.all(:conditions => { 
        :created_on => from..(to+1) # cheat -- +1 as time is from midnight
    }).map{|i| issue_report(i, from, to, 'NEW')}


    time_entries = TimeEntry.all(:conditions => {
        :spent_on => (from..to)
      }
    )
    issues_worked_on = time_entries.map(&:issue).compact.uniq.map{|i| issue_report(i, from, to, "WRKD")}


    remaining_issues = project.issues.find(:all,
      :conditions => {
        :status_id => IssueStatus.all(:conditions => {:is_closed => false}),
        :fixed_version_id => versions
      }
    ).map{|i| issue_report(i, from, to, "TODO")}
    

    all_issues = []
    (remaining_issues + new_issues + issues_worked_on).group_by{|i| i['id']}.each{|id,issues|
	all_issues << issues.first.merge(:why => issues.map{|i| i[:why]})
    }

    all_issues.each do |issue|
      issue[:why] ||= []
      issue[:why] << "NEW" if issue[:created_on] > from
      issue[:why] = issue[:why].sort.uniq.join(",")
    end

    all_issues
  end


  def issue_report(issue, from, to, why)
    time_spent_to_date = issue.time_entries.select{|t| t.spent_on <= to}.map(&:hours).sum
    time_spent_in_period = issue.time_entries.select{|t| (from..to).include? t.spent_on}.map(&:hours).sum

    remaining = if issue.closed?
      0.0
    else
      (issue.estimated_hours || 0.0) - time_spent_to_date
    end.abs

    issue.attributes.merge(
      :created_on => issue.created_on,
      :status   => issue.status.to_s,
      :project  => issue.project.to_s,
      :tracker  => issue.tracker.to_s,
      :priority => issue.priority.to_s,
      :time_spent_in_period => time_spent_in_period,
      :time_spent_to_date => time_spent_to_date,
      :remaining => remaining,
      :why => why
    )
  end


  def humanize_column_titles(report)
    report.column_titles = report.
      columns.
      map{|col| {col => col.to_s.humanize} }.
      inject({}) {|a,b| a.merge(b) }
  end
end


