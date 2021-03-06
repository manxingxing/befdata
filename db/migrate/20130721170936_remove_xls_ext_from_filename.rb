class RemoveXlsExtFromFilename < ActiveRecord::Migration
  def up
    Dataset.where('filename is not NULL').each do |dt|
      dt.update_attribute(:filename, File.basename(dt.filename, '.xls'))
    end
  end

  def down
  end
end
