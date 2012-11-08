class DatasetsController < ApplicationController

  before_filter :load_dataset, :only => [:download, :show, :edit, :edit_files, :update, :approve, :approve_predefined,
                                         :delete_imported_research_data_and_file, :destroy, :regenerate_download,
                                         :approval_quick, :batch_update_columns]

  before_filter :redirect_if_unimported, :only => [:download, :edit, :approve, :approve_predefined, :destroy,
                                                   :approval_quick, :batch_update_columns]

  skip_before_filter :deny_access_to_all

  access_control do
    allow all, :to => [:show, :index, :load_context, :download_excel_template, :importing]

    actions :download, :regenerate_download, :edit, :edit_files, :update, :approve, :approve_predefined,
      :approval_quick, :batch_update_columns do
      allow :admin
      allow :data_admin
      allow :owner, :of => :dataset
    end

    actions :delete_imported_research_data_and_file, :destroy do
      allow :admin
      allow :owner, :of => :dataset
    end

    action :download do
      allow :proposer, :of => :dataset
      allow logged_in, :if => :dataset_is_free_for_members
      allow logged_in, :if => :dataset_is_free_for_project_of_user
      allow all, :if => :dataset_is_free_for_public
    end

    actions :new, :create do
      allow logged_in
    end
  end

  def create
    # submitting neither title nor datafile
    if !params[:dataset] && !params[:datafile]
      flash[:error] = "No workbook given for upload"
      redirect_to :back and return
    end

    @dataset = Dataset.new

    # Upload option A - from workbook
    if params[:datafile]
      datafile = Datafile.new(params[:datafile])
      @dataset.upload_spreadsheet = datafile
      @dataset.import_status = 'new'
      unless datafile.save
        flash[:error] = datafile.errors.full_messages.to_sentence
        redirect_to(:back) and return
      end
    end

    # Upload option B - empty, only given title
    if params[:dataset] && !params[:datafile]
      @dataset.title = params[:dataset][:title]
    end

    if @dataset.save
      current_user.has_role! :owner, @dataset
      if datafile then
        @dataset.dataworkbook.members_listed_as_responsible[:found_users].each do |user|
          user.has_role!(:owner, @dataset)
        end
        @unfound_usernames = @dataset.dataworkbook.members_listed_as_responsible[:unfound_usernames]
      end
    else
      flash[:error] = @dataset.errors.full_messages.to_sentence
      flash[:error] << datafile.errors.full_messages.to_sentence if datafile
      redirect_to :back
    end
  end

  def update
    users_given_as_provenance = params[:people].blank? ? [] : User.find(params[:people])
    users_with_current_ownership = User.all.select {|u| u.has_role? :owner, @dataset}

    if !users_given_as_provenance.empty? then
      users_with_current_ownership.each do |u|
        u.has_no_role! :owner, @dataset
      end
      users_given_as_provenance.each do |u|
        u.has_role! :owner, @dataset
      end
    # but at least keep current_user if there would be nobody
    elsif users_with_current_ownership.empty? then
      current_user.has_role! :owner, @dataset
    end

    if @dataset.update_attributes(params[:dataset]) then
      redirect_to dataset_path
    else
      flash[:error] = @dataset.errors.full_messages.to_sentence
      render :create
    end
  end

  # to be used by the ajax import status query
  def importing
    @dataset = Dataset.find(params[:id], :select => ['id','import_status'])
    render :text => @dataset.import_status
  end

  def approve
    @predefined_columns = @dataset.predefined_columns.collect{|c| c.id}
    render :layout => 'approval'
  end

  def approval_quick
    @datagroups = Datagroup.order(:title)
    @datatypes = Datatypehelper.known
    render :layout => 'approval'
  end

  def batch_update_columns
    datacolumns = params[:datacolumn]
    changes = 0
    datacolumns.each do |hash|
      datacolumn = Datacolumn.find hash[:id]
      unless datacolumn.dataset == @dataset
        flash[:error] = "Updated datacolumns must be part of the dataset!"
        redirect_to approve_dataset_url(@dataset) and return
      end

      unless hash[:datagroup].blank?
        changes += 1
        datagroup = Datagroup.find(hash[:datagroup])
        datacolumn.approve_datagroup(datagroup)
      end

      unless hash[:import_data_type].blank?
        changes += 1
        datatype = hash[:import_data_type]
        datacolumn.approve_datatype datatype, current_user
      end
    end

    flash[:notice] = "Successfully approved #{changes} properties."
    redirect_to approve_dataset_url(@dataset)
  end

  def approve_predefined
    @dataset.approve_predefined_columns(current_user)

    if @dataset.columns_with_invalid_values_after_approving_predefined.blank?
      flash[:notice] = "All available columns were successfully approved."
    else
      still_unapproved_columns = @dataset.columns_with_invalid_values_after_approving_predefined
      flash[:error] = "Unfortunately we could not automatically validate entries in the following data columns:
        #{still_unapproved_columns.map{|c| c.columnheader}.join(', ')}"
      flash[:non_auto_approved] = still_unapproved_columns.map{|c| c.id}
    end
    redirect_to :back
  end

  def show
    trigger_import_if_nessecary

    @contacts = @dataset.owners
    @projects = @dataset.projects
    @freeformats = @dataset.freeformats :order => :file_file_name
    @datacolumns = @dataset.datacolumns

    respond_to do |format|
      format.html
      format.eml
      format.csv { render text: to_csv} 
    end
  end

  def to_csv 
    require 'csv'
    # This class renders the raw values of a dataset to a csv file. It iterates over the     
    # datacolumns and the sheetcells in each datacolumn to extract the right    
    # values of the sheetcells.                                                 
    # data_columns=Datacolumn.all(:conditions => ["dataset_id = ?", params[:id]], :order => "columnnr ASC").uniq

    # csv_raw_data_sheet=[0,0]

    data_columns=Datacolumn.all(:conditions => ["dataset_id = ?", 6], :order => "columnnr ASC").uniq
    CSV.generate do |csv|
      dataset_column=Array.new 
      dataset_value_array=Array.new 
      data_columns.each do |dc|
        dataset_column << dc.columnheader 
        dc.sheetcells.sort_by{|r| :row_number}.each do |sc|
          if sc.datatype && sc.datatype.is_category? && sc.category 
            dataset_column << sc.category.short
          elsif sc.datatype && sc.datatype.name.match(/^date/) && sc.accepted_value
            dataset_column << sc.accepted_value.to_date.to_s
          elsif sc.accepted_value
            dataset_column << sc.accepted_value
          else
            dataset_column << sc.import_value
          end
        end
        dataset_value_array << dataset_column 
        # csv << dataset_column
        dataset_column = Array.new 
      end
      csv << dataset_value_array.transpose
    end
  end

  def download
    @dataset.log_download(current_user)
    send_file(@dataset.generated_spreadsheet.path,
              :filename => "download_#{@dataset.downloads}_#{@dataset.filename}")
  end

  def regenerate_download
    @dataset.enqueue_to_generate_download(:high)
    redirect_to :action => :show
  end

  def download_excel_template
    send_file Rails.root.join('files', 'template','befdata_workbook_empty.xls'),
        :filename=>'emtpy_excel_template.xls',
        :disposition => 'attachment'
  end

  def edit_files
    unless @dataset.import_status.nil? || @dataset.import_status.starts_with?('finished','error')
      redirect_to(:action => 'show') and return
    end
    @freeformats = @dataset.freeformats :order => :file_file_name
  end


  def delete_imported_research_data_and_file
    if !params[:datafile] then
      flash[:error] = "No filename given"
      redirect_to :back and return
    end
    new_datafile = Datafile.new(params[:datafile])
    if new_datafile.save
      @dataset.delete_imported_research_data_and_file
      @dataset.upload_spreadsheet = new_datafile
      @dataset.filename = new_datafile.file_file_name
      @dataset.import_status = 'new'
      @dataset.save
      flash[:notice] = "Research data has been replaced."
      redirect_to(:action => 'show')
    else
      flash[:error] = new_datafile.errors.full_messages.to_sentence
      redirect_to edit_dataset_path(@dataset)
    end
  end

  def destroy
    @dataset.destroy
    flash[:notice] = "The dataset was successfully deleted."
    redirect_to data_path
  end

  private

  def load_dataset
    @dataset = Dataset.find(params[:id])
  end

  def trigger_import_if_nessecary
    if @dataset.import_status == 'new'
      @book = Dataworkbook.new(@dataset.upload_spreadsheet)
      return unless @book.columnheaders_unique?

      @dataset.import_status = 'queued'
      @dataset.save
      @dataset.delay.import_data
    end
  end

  def redirect_if_unimported
    if @dataset.import_status != 'finished' && @dataset.has_research_data?
      redirect_to :action => 'show'
    end
  end

end
