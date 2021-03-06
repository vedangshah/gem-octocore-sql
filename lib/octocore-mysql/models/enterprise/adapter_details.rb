require 'active_record'
require 'octocore-mysql/record'

module Octo
	# Store adapter details of Enterprise
  class AdapterDetails < ActiveRecord::Base
    include Octo::Record

    belongs_to :enterprise, class_name: 'Octo::Enterprise'

    key :adapter_id, :int
    key :enable, :boolean
    
    column :settings, :text

  end
end
