require "rubygems"
require "active_record"

class CreateAppLogin < ActiveRecord::Migration

  def self.up
    create_table :app_login do |t|
      t.column :created_at, :timestamp, null: false
      t.column :userid, :integer, null: false
    end
  end

  def self.down
    drop_table :app_login
  end
 
end