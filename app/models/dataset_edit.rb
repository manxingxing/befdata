class DatasetEdit < ActiveRecord::Base
  belongs_to :dataset
  attr_accessible :description, :submitted

  validates_presence_of :dataset, :description
  #validate :only_one_unsubmitted_per_dataset

  #def only_one_unsubmitted_per_dataset
  #  unsubmitted_edits = self.dataset.dataset_edits.where(:submitted => 'false')
  #  unless unsubmitted_edits.count == 0 || unsubmitted_edits.first == self
  #    errors.add(:submitted, 'only one unsubmitted edit per dataset allowed')
  #  end
  #end

  def add_line!(line)
    unless self.description =~ /- #{line}/
      self.description ||= ''
      self.description = self.description + "\r\n- #{line}"
    end
    self.touch
    self.save
  end

  def notify(params)
    return "true" if params[:notify].nil?
    dataset = self.dataset
    proposers = []
    downloaders = []
    # collect

    if params[:notify][:downloaders]
      downloaders = dataset.dataset_downloads.collect{|dl| dl.user}
    end
    if params[:notify][:proposers]
      proposers = dataset.paperproposals.collect{|pp| pp.author}
    end
    #normalize
    [downloaders, proposers].each do |a|
      a.flatten!
      a.uniq!
      a.reject!{|x| dataset.owners.include?(x)}
    end
    downloaders = downloaders - proposers # proposers are more important

    #send notification
    proposers.each{|u| NotificationMailer.delay.dataset_edit(u, self, :proposer)}
    downloaders.each{|u| NotificationMailer.delay.dataset_edit(u, self, :downloader)}

    'p/d' + proposers.collect{|u|u.id}.to_s + downloaders.collect{|u|u.id}.to_s
  end

end
