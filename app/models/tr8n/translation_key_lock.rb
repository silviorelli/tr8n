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
#-- Tr8n::TranslationKeyLock Schema Information
#
# Table name: tr8n_translation_key_locks
#
#  id                    INTEGER     not null, primary key
#  translation_key_id    integer     not null
#  language_id           integer     not null
#  translator_id         integer     
#  locked                boolean     
#  created_at            datetime    not null
#  updated_at            datetime    not null
#
# Indexes
#
#  tr8n_tkl_tl    (translation_key_id, language_id) 
#
#++

class Tr8n::TranslationKeyLock < ActiveRecord::Base
  self.table_name = :tr8n_translation_key_locks
  attr_accessible :translation_key_id, :language_id, :translator_id, :locked
  attr_accessible :language, :translator, :translation_key

  after_save      :clear_cache
  after_destroy   :clear_cache

  belongs_to :translation_key,  :class_name => "Tr8n::TranslationKey"
  belongs_to :language,         :class_name => "Tr8n::Language"
  belongs_to :translator,       :class_name => "Tr8n::Translator"

  alias :key :translation_key
  
  def self.cache_key(locale, key)
    "key_lock_[#{locale}]_[#{key}]"
  end

  def cache_key
    self.class.cache_key(language.locale, translation_key.key)
  end

  def self.find_or_create(translation_key, language)
    lock = where("translation_key_id = ? and language_id = ?", translation_key.id, language.id).first
    
    # MODIFIED - does not save the label if comes from tr8n backend - avoid saving the label
    lock || if Tr8n::Config.current_source.source.include? "/tr8n/"
        new(:translation_key => translation_key, :language => language)
      else
        create(:translation_key => translation_key, :language => language)
      end 
  end

  def self.for(translation_key, language)
    Tr8n::Cache.fetch(cache_key(language.locale, translation_key.key)) do 
      find_or_create(translation_key, language)
    end
  end

  def lock!(translator = Tr8n::Config.current_translator)
    update_attributes(:locked => true, :translator => translator)
    translator.locked_translation_key!(translation_key, language)
    language.total_metric.update_metrics!
  end

  def unlock!(translator = Tr8n::Config.current_translator)
    update_attributes(:locked => false, :translator => translator)
    translator.unlocked_translation_key!(translation_key, language)
  end
  
  def clear_cache
    Tr8n::Cache.delete(cache_key)
  end
end
