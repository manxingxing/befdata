class DatagroupsController < ApplicationController

  skip_before_filter :deny_access_to_all
  access_control do
    actions :index, :show do
      allow logged_in
    end
  end

  def index
    @datagroups = Datagroup.order(:title)
  end

  def show
    @datagroup = Datagroup.find params[:id]
  end

end