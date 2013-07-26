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
#-- Tr8n::Translation Schema Information
#
# Table name: tr8n_translations
#
#  id                    INTEGER       not null, primary key
#  translation_key_id    integer       not null
#  language_id           integer       not null
#  translator_id         integer       not null
#  label                 text          not null
#  rank                  integer       default = 0
#  approved_by_id        integer(8)    
#  rules                 text          
#  synced_at             datetime      
#  created_at            datetime      not null
#  updated_at            datetime      not null
#
# Indexes
#
#  tr8n_trn_c       (created_at) 
#  tr8n_trn_tktl    (translation_key_id, translator_id, language_id) 
#  tr8n_trn_t       (translator_id) 
#
#++

class Tr8n::Translation < ActiveRecord::Base
  self.table_name = :tr8n_translations
  attr_accessible :translation_key_id, :language_id, :translator_id, :label, :rank, :approved_by_id, :rules, :synced_at
  attr_accessible :language, :translator, :translation_key

  after_create    :distribute_notification
  after_save      :update_cache
  after_destroy   :update_cache

  belongs_to :language,         :class_name => "Tr8n::Language"
  belongs_to :translation_key,  :class_name => "Tr8n::TranslationKey"
  belongs_to :translator,       :class_name => "Tr8n::Translator"

  has_many :translation_key_sources,  :class_name => "Tr8n::TranslationKeySource",  :through => :translation_key
  has_many :translation_sources,      :class_name => "Tr8n::TranslationSource",     :through => :translation_key_sources
  
  has_many   :translation_votes, :class_name => "Tr8n::TranslationVote", :dependent => :destroy
  
  serialize :rules
    
  alias :key :translation_key
  alias :votes :translation_votes

  # TODO: move this to config file
  VIOLATION_INDICATOR = -10

  def vote!(translator, score)
    score = score.to_i
    vote = Tr8n::TranslationVote.find_or_create(self, translator)
    vote.update_attributes(:vote => score.to_i)
    
    Tr8n::Notification.distribute(vote)

    update_rank!
    
    # update the translation key timestamp
    key.touch

    self.translator.update_rank!(language) if self.translator
    
    # add the translator to the watch list
    self.translator.update_attributes(:reported => true) if score < VIOLATION_INDICATOR
    
    translator.voted_on_translation!(self)
    translator.update_metrics!(language)
    translation_key.update_metrics!(language)
  end
  
  def update_rank!
    new_rank = 0
    Tr8n::TranslationVote.where(:translation_id => self.id).each do |tv|
      next unless tv.translator
      new_rank += (tv.translator.voting_power * tv.vote)
    end
    update_attributes(:rank => new_rank)
  end
  
  def reset_votes!(translator)
    Tr8n::TranslationVote.delete_all(["translation_id = ?", self.id])
    vote!(translator, 1)
  end
  
  # TODO: move this stuff to decorators
  def rank_style(rank)
    Tr8n::Config.default_rank_styles.each do |range, color|
      return color if range.include?(rank)
    end
    "color:grey"
  end
  
  # TODO: move this stuff to decorators
  def rank_label
    return "<span style='color:grey'>0</span>" if rank.blank?
    
    prefix = (rank > 0) ? "+" : ""
    "<span style='#{rank_style(rank)}'>#{prefix}#{rank}</span>".html_safe 
  end

  # populate language rules from the internal rules hash
  def rules
    super_rules = super
    return nil if super_rules == nil
    return nil unless super_rules.class.name == 'Array'
    return nil if super_rules.size == 0

    @loaded_rules ||= begin
      rulz = []
      super_rules.each do |rule|
        [rule[:rule_id]].flatten.each do |rule_id|
          language_rule = Tr8n::LanguageRule.by_id(rule_id)
          rulz << rule.merge({:rule => language_rule}) if language_rule
        end
      end
      rulz
    end
  end

  # generates a hash of token => rule_id
  # TODO: is this still being used? 
  # Warning: same token can have multiple rules in a single translation
  def rules_hash
    return nil if rules.nil? or rules.empty? 
    
    @rules_hash ||= begin
      rulz = {}
      rules.each do |rule|
        rulz[rule[:token]] = rule[:rule_id]  
      end
      rulz
    end
  end

  # deprecated - api_hash should be used instead
  def rules_definitions
    return nil if rules.nil? or rules.empty? 
    @rules_definitions ||= begin
      rulz = {}
      rules.each do |rule|
        rulz[rule[:token].clone] = rule[:rule].to_hash  
      end
      rulz
    end
  end

  # TODO: move to decorators
  def context
    return nil if rules.nil? or rules.empty? 
    
    @context ||= begin
      context_rules = []  
      rules.each do |rule|
        context_rules << "<strong>#{rule[:token]}</strong> #{rule[:rule].description}" 
      end
      context_rules.join(" and ").html_safe
    end
  end

  # checks if the translation is valid for the given tokens
  def matches_rules?(token_values)
    return true if rules.nil? # doesn't have any rules
    return false if rules.empty?  # had some rules that have been removed
    
    rules.each do |rule|
      token_value = token_values[rule[:token].to_sym]
      token_value = token_value.first if token_value.is_a?(Array)
      result = rule[:rule].evaluate(token_value)
      return false unless result
    end
    
    true
  end
  
  # used by the permutation generator
  def matches_rule_definitions?(new_rules_hash)
    rules_hash == new_rules_hash
  end

  def self.default_translation(translation_key, language, translator)
    trans = where("translation_key_id = ? and language_id = ? and translator_id = ? and rules is null", translation_key.id, language.id, translator.id).order("rank desc").first
    return trans if trans
    label = translation_key.default_translation if translation_key.is_a?(Tr8n::RelationshipKey)
    new(:translation_key => translation_key, :language => language, :translator => translator, :label => label || translation_key.sanitized_label)
  end

  def blank?
    self.label.blank?    
  end

  def uniq?
    # for now, treat all translations as uniq
    return true
    
    trns = self.class.where("translation_key_id = ? and language_id = ? and label = ?", translation_key.id, language.id, label)
    trns = trns.where("id <> ?", self.id) if self.id
    trns.count == 0
  end
  
  def clean?
    language.clean_sentence?(label)
  end
  
  def can_be_edited_by?(editor)
    return false if translation_key.locked?
    translator == editor
  end

  def can_be_deleted_by?(editor)
    return false if translation_key.locked?
    return true if editor.manager?
    
    translator == editor
  end

  def save_with_log!(translator)
    if self.id
      translator.updated_translation!(self) if changed?
    else  
      translator.added_translation!(self)
    end
    
    save
  end
  
  def destroy_with_log!(translator)
    translator.deleted_translation!(self)
    
    destroy
  end

  def distribute_notification
    Tr8n::Notification.distribute(self)
  end

  def update_cache
    # Tr8n::Cache.delete("translations_#{language.locale}_#{translation_key.key}") if language and translation_key
    language.translations_changed! if language
    translation_key.translations_changed!(language) if translation_key
  end
  
  ###############################################################
  ## Synchronization Methods
  ###############################################################
  # generates the hash without rule ids, but with full definitions
  def mark_as_synced!
    update_attributes(:synced_at => Time.now + 2.seconds)
  end

  def rules_sync_hash(opts = {})
    @rules_sync_hash ||= (rules || []).collect{|rule| rule[:rule].to_api_hash(opts.merge(:token => rule[:token]))}
  end

  def rules_api_hash(opts = {})
    return nil if rules.nil? or rules.empty? 
    rulz = {}
    rules.each do |rule|
      rulz[rule[:token]] ||= []
      rulz[rule[:token]] << {
        :type => rule[:rule].class.dependency,
        :key => rule[:rule].keyword  
      }
    end
    rulz
  end

  # serilaize translation to API hash to be used for synchronization
  def to_api_hash(opts = {})
    return {"locale" => language.locale, "label" => label, "rules" => rules_sync_hash(opts)} if opts[:comparible]
    
    hash = {"id" => id, "locale" => language.locale, "label" => label, "rank" => rank, "rules" => rules_sync_hash(opts)}
    if translator
      if opts[:include_translator] # tr8n.net => local = include full translator info
        hash["translator"] = translator.to_api_hash(opts)
      elsif translator.remote_id  # local => tr8n.net = include only the remote id of the translator if the translator is linked 
        hash["translator_id"] = translator.remote_id
      end  
    end  
    hash  
  end

  # create translation from API hash for a specific key
  def self.create_from_sync_hash(tkey, translator, thash, opts = {})
    return if thash["label"].blank?  # don't add empty translations
    
    lang = Tr8n::Language.for(thash["locale"])
    return unless lang  # don't add translations for an unsupported language

    # generate rules for the translation
    rules = []    
    if thash["rules"] and thash["rules"].any?
      thash["rules"].each do |rhash|
        rule = Tr8n::LanguageRule.create_from_sync_hash(lang, translator, rhash, opts)
        return unless rule # if the rule has not been created, we should not even add the translation
        rules << {:token => rhash["token"], :rule_id => rule.id}
      end
    end
    rules = nil if rules.empty?
    
    tkey.add_translation(thash["label"], rules, lang, translator)
  end
    
  ###############################################################
  ## Search Methods
  ###############################################################
  def self.filter_status_options
    [["all translations", "all"], 
     ["accepted translations", "accepted"], 
     ["pending translations", "pending"], 
     ["rejected translations", "rejected"]].collect{|option| [option.first.trl("Translation filter status option"), option.last]}    
  end
  
  def self.filter_submitter_options
    [["anyone", "anyone"], 
     ["me", "me"]].collect{|option| [option.first.trl("Translation filter submitter option"), option.last]}
  end
  
  def self.filter_date_options
    [["any date", "any"], 
     ["today", "today"], 
     ["yesterday", "yesterday"], 
     ["in the last week", "last_week"]].collect{|option| [option.first.trl("Translation filter date option"), option.last]}
  end
  
  def self.filter_order_by_options
    [["date", "date"], 
     ["rank", "rank"]].collect{|option| [option.first.trl("Translation filter order by option"), option.last]}
  end
  

  def self.filter_group_by_options
    [["nothing", "nothing"], 
     ["translator", "translator"], 
     ["context rule", "context"], 
     ["rank", "rank"], 
     ["date", "date"]].collect{|option| [option.first.trl("Translation filter group by option"), option.last]}
  end
  
  def self.for_params(params, language = Tr8n::Config.current_language)
    results = self.where("language_id = ?", language.id)

    # only translations from the selected application
    if params[:application]
      results = results.joins(:translation_sources).where("tr8n_translation_sources.application_id = ?", params[:application].id)
    end
    
    # ensure that only allowed translations are visible
    allowed_level = Tr8n::Config.current_user_is_translator? ? Tr8n::Config.current_translator.level : 0
    results = results.joins(:translation_key).where("tr8n_translation_keys.level <= ?", allowed_level) 
    
    if params[:only_phrases]  
      results = results.where("tr8n_translation_keys.type is null or tr8n_translation_keys.type = ? or tr8n_translation_keys.type = ?", 'Tr8n::TranslationKey', 'TranslationKey')
    end

    results = results.where("tr8n_translations.label like ?", "%#{params[:search]}%") unless params[:search].blank?
  
    if params[:with_status] == "accepted"
      results = results.where("tr8n_translations.rank >= ?", Tr8n::Config.translation_threshold)
    elsif params[:with_status] == "pending"
      results = results.where("tr8n_translations.rank >= 0 and tr8n_translations.rank < ?", Tr8n::Config.translation_threshold)
    elsif params[:with_status] == "rejected"
      results = results.where("tr8n_translations.rank < 0")
    end
    
    if params[:submitted_by] == "me"
      results = results.where("tr8n_translations.translator_id = ?", Tr8n::Config.current_user_is_translator? ? Tr8n::Config.current_translator.id : 0)
    end
    
    if params[:submitted_on] == "today"
      date = Date.today
      results = results.where("tr8n_translations.created_at >= ? and tr8n_translations.created_at < ?", date, date + 1.day)
    elsif params[:submitted_on] == "yesterday"
      date = Date.today - 1.days
      results = results.where("tr8n_translations.created_at >= ? and tr8n_translations.created_at < ?", date, date + 1.day)
    elsif params[:submitted_on] == "last_week"
      date = Date.today - 7.days
      results = results.where("tr8n_translations.created_at >= ? and tr8n_translations.created_at < ?", date, Date.today)
    end    
    results.uniq
  end 
    
end
