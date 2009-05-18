$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'bankjob/support.rb'
require 'bankjob/statement.rb'
require 'bankjob/transaction.rb'
require 'bankjob/scraper.rb'
require 'bankjob/payee.rb'

module Bankjob
  BANKJOB_VERSION = '0.5.2' unless defined?(BANKJOB_VERSION)
end
