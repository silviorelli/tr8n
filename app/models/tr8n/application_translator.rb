#--
# Copyright (c) 2010-2013 Michael Berkovich, tr8nhub.com
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++
#
#-- Tr8n::ApplicationTranslator Schema Information
#
# Table name: tr8n_application_translators
#
#  id                INTEGER     not null, primary key
#  application_id    integer     
#  translator_id     integer     
#  language_id       integer     
#  created_at        datetime    not null
#  updated_at        datetime    not null
#  manager           boolean     
#  inline_mode       boolean     
#
# Indexes
#
#  tr8n_app_trn_lang_id    (language_id) 
#  tr8n_app_trn_trn_id     (translator_id) 
#  tr8n_app_trn_comp_id    (application_id) 
#
#++

class Tr8n::ApplicationTranslator < ActiveRecord::Base
  self.table_name = :tr8n_application_translators
  attr_accessible :application, :translator, :language, :manager

  belongs_to :application, :class_name => 'Tr8n::Application'
  belongs_to :translator, :class_name => 'Tr8n::Translator'
  belongs_to :language, :class_name => 'Tr8n::Language'

  after_create :distribute_notification

  def self.find_or_create(application, translator)
    where("application_id = ? and translator_id = ?", application.id, translator.id).first || create(:application => application, :translator => translator) 
  end

  def self.touch(application, translator)
    find_or_create(application, translator).touch
  end

  def distribute_notification
    Tr8n::Notification.distribute(self)    
  end

end
