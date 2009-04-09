
require 'rubygems'
require 'mechanize'
require 'logger'
require 'bankjob'

module Bankjob

  ##
  # The Scraper class is the basis of all Bankjob web scrapers for scraping specific
  # bank websites.
  # 
  # To create your own scraper simply subclass Scraper and be sure to override
  # the method +scrape_statement+ to perform the scraping and return a
  # Bankjob::Statement object.
  #
  # Scraper provides some other optional methods to help you build Statements:
  #
  # +currency+:: use this class attribute to set the OFX currency at the top of
  #              your Scraper subclass definition. E.g.:
  #
  # 
  #                 class MyScraper < Scraper
  #                     currency "USD"
  #                     ...
  # 
  #              It defaults to "EUR" for euros.
  #
  # +decimal+:: use this class attribute to set the decimal separator at the top of
  #             your Scraper subclass definition. E.g.:
  # 
  #                 class MyScraper < Scraper
  #                     decimal ","
  #                     ...
  # 
  #             It defaults to "." (period), the common alternative being "," (comma)
  #
  #             Note that this should be set to the separator used in the +amount+
  #             attribute of the Transaction objects your Scraper creates. If, say,
  #             you deliberately scrape values like "12,34" and convert them to
  #             "12.34" before storing them in your Transaction, then leave the
  #             decimal as ".".
  #             If you choose to store the Transaction amount with as "12,34",
  #             however, the +decimal+ setting becomes important when calling
  #             Transaction#real_amount to get the amount as a Float upon which
  #             calculations can be performed.
  #
  # +options+:: holds the command line options provided when Bankjob was launched.
  #             Use this attribute to get access to global options. For your scraper
  #             specific options use the array passed into +scrape_statement+ instead.
  #             (See #options below for more advice on how to use this)
  #
  # +logger+:: holds the logger initialized by Bankjob based on the command line
  #            options. Use this to attribute to log information, warnings and debug messages
  #            from your logger.
  #            (See #logger below for more advice on how to use this)
  # 
  # +create_statement+:: creates a new empty Statement object with the appropriate
  #                      default attributes (that is, the right currency)
  #                      Use this in your Scraper to instantiate new Statement objects.
  #                      
  # +create_transaction+:: creates a new empty Transaction object with the appropriate
  #                        default attributes (that is, the right decimal separator) 
  #                        Use this in your Scraper to instantiate new Transaction objects.
  #
  # +transaction_rule+:: registers a rule to be applied to all transactions after the 
  #                      statement has been scraped.
  #                      Define as many of these as you need in your craper to build better
  #                      organized Transaction objects with clearer descriptions of the 
  #                      transaction, etc.
  #
  # Here is an example of a simple (but incomplete) scraper.
  # Note that all of the scraping and parsing is in the +scrape_statement+ method, although
  # a lot of the details of Hpricot parsing are left up to the imagination of the reader.
  #
  # When creating a scraper yourself look in the +scrapers+ directory of the bankjob gem
  # to see some more useful examples.
  #
  #   class AcmeBankScraper < Scraper
  #     #####
  #     # 1. Set up the Scraper properties for currency and separator
  #     #    (this is optional)
  #
  #     currency "EUR"   # set the currency (EUR is the default anyway but just to demo..)
  #     decimal ","      # set the decimal separator to comma instead of .
  #
  #     #####
  #     # 2. Create some rules to post-process my transactions
  #     #    (this is optional but is easier to maintain than manipulating
  #     #     the values in the scraper itself)
  #
  #     # rule to set negative transactions as debits
  #     transaction_rule do |tx|
  #       tx.type = "DEBIT" if (tx.real_amount < 0 and tx.type == "OTHER")
  #     end
  #
  #     # General description parsing rule
  #     transaction_rule do |tx|
  #       case tx.description
  #         when /ATM/i
  #           tx.type = "ATM"
  #         when /ELEC PURCHASE/
  #           tx.description.gsub!(/ELEC PURCHASE \d+/, "spent with ATM card: ")
  #       end
  #     end
  #
  #     #####
  #     # 3. Implement main engine of the scraper
  #     #    (this is essential and where 99% of the work is)
  #   
  #    def scrape_statement(args)
  #
  #      logger.debug("Reading debug input html from #{options.input} instead of scraping the real website.")
  #      agent = WWW::Mechanize.new
  #      agent.user_agent_alias = 'Windows IE 6' # pretend that we're IE 6.0
  #      # navigate to the login page
  #      login_page = agent.get("http://mybank.com/login")
  #      # find login form, fill it out and submit it
  #      form  = login_page.forms.name('myBanksLoginForm').first
  #      # Mechanize creates constants like USERNAME for the form element it finds with that name
  #      form.USERNAME = args[0]   # assuming -scraper_args "user password"
  #      form.PASSWORD = args[1]
  #      agent.submit(form)
  #      sleep 3  #wait while the login takes effect
  #
  #      transactions_page = agent.get("http://mybank.com/transactions")
  #      statement = create_statement
  #
  #      # ... go read the Hpricot documentation to work out how to get your transactions out of
  #      #     the transactions_page and create a new transaction object for each one
  #      #     We're going to gloss over that part here ....
  #      
  #      table = # use Hpricot to get the html table element assuming your transactions are in a table
  #      rows = (table/"tr[@valign=top]")  # works for a table where the rows needed have the valign attr set to top
  #      rows.each do |row|
  #        transaction = create_transaction
  #        transaction.date = #... scrape a date here
  #        ...
  #        statement.transactions <<
  #      end
  #    end
  #  end
  #
  #--
  # (Non RDOC comment) There are two parts to the Scraper class:
  # - the public part which defines the
  #   method to be overridden in subclasses and provides utility methods and attributes;
  # - the private internal part which handles the mechanics of registering a
  #   subclass as the scraper to be used, setting the currency and decimal attributes
  #   and registering transaction rules
  #
  #
  class Scraper

    ##
    # Provides access to a logger instance created in the BankjobRunner which
    # subclasses can use for logging if they need to.
    #
    # To use this in your own scraper, use code like:
    #
    #   include 'logger'
    #   ...
    #   logger.debug("MyScraper is scraping the page at #{my_url}")
    #   logger.info("MyScraper fetched new statement from MyBank and has been sitting in my chair")
    #   logger.warn("MyScraper's been sitting in MY chair!")
    #   logger.fatal("MyScraper's been sitting in MY CHAIR and IT'S ALL BROKEN!")
    #
    attr_accessor :logger

    ##
    # Provides access to the command line options which subclasses can use it if
    # they need access to the global options used to launch Bankjob
    #
    # To use this in your own scraper, use code like:
    #
    #   if (options.input?) then
    #     print "the input html file for debugging is #{options.input}
    #   end
    #
    attr_accessor :options

    ##
    # Returns the decimal separator for this scraper
    # This is typically set in the scraper class using the "decimal" directive.
    #
    def decimal
      @@decimal
    end

    ## 
    # Returns the OFX currency for this scraper.
    # This is typically set in the scraper class using the "currency" directive.
    #
    def currency
      @@currency
    end

    ##
    # Sets the decimal separator for the money amounts used in the data fetched
    # by this scraper.
    # The scraper class can use this as a directive to set the separator so:
    #   decimal ","
    #
    # Defaults to period ".", but will typically need to be set as a comma in
    # european websites
    #
    def self.decimal(decimal)
      @@decimal = decimal
    end

    ##
    # Sets the OFX currency name for use in the OFX statements produced by
    # this scraper.
    #
    # The scraper class can use this as a directive to set the separator so:
    #   currency "USD"
    #
    # Defaults to EUR
    #
    def self.currency(currency)
      @@currency = currency
    end

    ##
    # Sets the account number for statements produced by this statement.
    #
    # The scraper class can use this as a directive to set the number so:
    #   account_number "12345678"
    #
    # Must be a string from 1 to 22 chars in length
    #
    # This will be used by the create_statement method to set the account,
    # but the scraper may ignore this and simply construct its own statements
    # or change the number using the accessor: statement.account_number =
    # after constructing it.
    #
    # The scraper class can use this as a directive to set the separator so:
    #   currency "USD"
    #
    # Defaults to EUR
    #
    def self.account_number(account_number)
      @@account_number = account_number
    end

    ##
    # Sets the account type for statements produced by this statement.
    #
    # The scraper class can use this as a directive to set the type so:
    #   account_type Statement::SAVINGS
    #
    # Must be a string based on one of the constants in Statement
    #
    # This will be used by the create_statement method to set the account type,
    # but the scraper may ignore this and simply construct its own statements
    # or change the type using the accessor: statement.account_type =
    # after constructing it.
    #
    # Defaults to Statement::CHECKING
    #
    def self.account_type(account_type)
      @@account_type = account_type
    end

    ##
    # Sets the bank identifier for statements produced by this statement.
    #
    # The scraper class can use this as a directive to set the number so:
    #   bank_id "12345678"
    #
    # Must be a string from 1 to 9 chars in length
    #
    # This will be used by the create_statement method to set the bank id,
    # but the scraper may ignore this and simply construct its own statements
    # or change the number using the accessor: statement.bank_id =
    # after constructing it.
    #
    # Defaults to blank
    #
    def self.bank_id(bank_id)
      @@bank_id = bank_id
    end

    ##
    # ScraperRule is a struct used for holding a rule body with its priority.
    # Users can create transaction rules in their Scraper subclasses using
    # the Scraper#ransaction_rule method.
    ScraperRule = Struct.new(:priority, :rule_body)

    ##
    # Processes a transaction after it has been created to allow it to be manipulated
    # into a more useful form for the client.
    #
    # For example, the transaction description might be simplified to remove certain
    # common strings, or the Payee details might be extracted from the description.
    #
    # Implementing this as a class method using a block permits the user to add
    # implement transaction processing rules by calling this method several times
    # rather than implementing a single method (gives it a sort of DSL look)
    #
    # E.g. 
    #    # This rule detects ATM withdrawals and modifies
    #    # the description and sets the the type it uses
    #    transaction_rule do |tx|
    #      if (tx.real_amount < 0)
    #        if tx.raw_description =~ /WDR.*ATM\s+\d+\s+/i
    #          # $' holds whatever is after the pattern match - usually the ATM location
    #          tx.description = "ATM withdrawal at #{$'}"
    #          tx.type = Transaction::ATM
    #        end
    #      end
    #    end
    #
    #
    # A transaction rule can optionally specifiy a +priority+ - any integer value.
    # The default priority is zero, with lower priority rules being executed last.
    #
    # The final order in which transaction rules will be executed is thus:
    # * rules with a higher priority value will be executed before rules with
    #   a lower priority no matter where they are declared
    # * rules of the same priority declared in the same class wil be executed in
    #   the order in which they are declared - top rules first
    # * rules in parent classes are executed before rules in subclasses of the
    #   same priority.
    #
    # If you really want a rule to be fired last, and you want to allow for
    # subclasses to your scraper, use a negative priority like this:
    #
    #    transaction_rule(-999) do |tx|
    #      puts "I get executed last"
    #    end
    #
    def self.transaction_rule(priority = 0, &rule_body)
      @@transaction_rules ||= []
      rule = ScraperRule.new(priority, rule_body)
      # Using Array#sort won't work on here (or later) because it doesn't preserve
      # the order of the rules with equal priorty - thus breaking the 
      # rules of priority detailed above. So we have to sort as we insert
      # each new rule in order without messing up the equal-priority order
      # which is first come, first in.
      # Imagine we have a set of rule already inorder of priority such as:
      #    A:999, B:999, C:0, D:0, E:-999, F:-999
      # we're now adding X:0, which should come after D since it's added later
      # First we reverse the array to get
      #    F:-999, E:-999, D:0, C:0, B:999, A:999
      # then we find the first element with priority greater than or equal to
      # X's priority of 0. Just greater than won't work because we'll end up
      # putting X between B and C whereas it was added after D.
      # So we find D, then get it's index in the original array which is 3
      # which tells us we can insert X at 4 into the forward-sorted rules
      #
      rev = @@transaction_rules.reverse
      last_higher_or_equal = rev.find { |r| r.priority.to_i >= priority }
      if last_higher_or_equal.nil?
        # insert a the start of the list
        @@transaction_rules.insert(0, rule)
      else
        index_of_last = @@transaction_rules.index(last_higher_or_equal)
        # now insert it after the last higher or equal priority rule
        @@transaction_rules.insert(index_of_last + 1, rule)
      end
    end

    ##
    # Runs through all of the rules registered with calls to +transaction_rule+
    # and applies them to each Transaction in the specified +statement+.
    #
    # Bankjob calls this after +scrape_statement+ and before writing out the
    # statement to CSV or OFX
    #
    def self.post_process_transactions(statement) #:nodoc:
      if defined?(@@transaction_rules)
        @@transaction_rules.each do |rule|
          statement.transactions.each do |transaction|
            rule.rule_body.call(transaction)
          end
        end
      end
      return statement
    end

    ##
    # Scrapes a website to produce a new Statement object.
    #
    # This is the one method which a Scraper *must* implement by overriding
    # this method.
    #
    # Override this in your own Scraper to use Mechanize and Hpricot (or
    # some other mechanism if you prefer) to parse your bank website
    # and create a Bankjob::Statement object to hold the data.
    #
    # The implementation here will raise an error if not overridden.
    #
    def scrape_statement
      raise "You must override the instance method scrape_statement in your scraper!"
    end

    ##
    # Creates a new Statement.
    #
    # Calling this method is the preferred way of creating a new Statement object
    # since it sets the OFX currency (and possibly other attributes) based on the
    # values set in the definition of the Scraper subclass.
    # It is otherwise no different, however, than calling Statement.new() yourself.
    #
    def create_statement
      statement = Statement.new(@@account_number, @@currency)
      statement.bank_id = @@bank_id if defined?(@@bank_id)
      statement.account_type = @@account_type if defined?(@@account_type)
      return statement
    end

    ##
    # Creates a new Transaction.
    #
    # Calling this method is the preferred way of creating a new Transaction object
    # since it sets the decimal separator (and possibly other attributes) based on the
    # values set in the definition of the Scraper subclass.
    #
    # It is otherwise no different, however, than calling Transaction.new() yourself.
    #
    def create_transaction
      Transaction.new(@@decimal)
    end

    ##
    # Private
    #
    # The internal workings of the Scraper come after this point - they
    # are not documented in RDOC
    ##

    #SCRAPER_INTERFACE is the list of methods that a scraper must define
    SCRAPER_INTERFACE = [:scrape_statement]

    # set up the directories in which user's scrapers will be sought
    HOME_DIR = File.dirname(__FILE__);
    SCRAPERS_DIR = File.join(HOME_DIR, "..", "..", "scrapers")

    ##
    # +inherited+ is always called when a class extends Scraper.
    # The subclass itself is passed in as +scraper_class+ alllowing
    # us to register it to be instantiated later
    #
    def self.inherited(scraper_class) #:nodoc:
      # verify that the scraper class indeed defines the necessary methods
      SCRAPER_INTERFACE.each do |method|
        if (not scraper_class.public_method_defined?(method))
          raise "Invalid scraper: the scraper class #{scraper_class.name} does not define the method #{method}"
        end
      end
      # in the future we might keep a registry of scrapers but for now
      # we assume there will always be one, and just register that class
      @@last_scraper_class = scraper_class
    end

    ##
    # This is the main method of the dynamic Scraper-loader: It loads
    # the actual scraper ruby file and initializes the class therein.
    #
    # Note that no assumption is made about the name of the class
    # defined within the specified +scraper_filename+. Rather, the
    # +self.inherited+ method will hold a reference to the last
    # class loaded that extends Bankjob::Scraper and that reference
    # is used here to initialize the class immediately after load()
    # is called on the specified file.
    #
    def self.load_scraper(scraper_filename, options, logger) #:nodoc:
      # temporarily add the same dir as bankjob and the scrapers dir
      # to the ruby LOAD_PATH for finding the scraper
      begin
      	$:.unshift(HOME_DIR)
        $:.unshift(SCRAPERS_DIR)
        logger.debug("About to load the scraper file named #{scraper_filename}")
        load(scraper_filename)
      rescue Exception => e
        logger.error("Failed to load the scraper file #{scraper_filename} due to #{e.message}.\n\t#{e.backtrace[0]}")
      ensure
      	$:.delete(SCRAPERS_DIR)
        $:.delete(HOME_DIR)
      end
     
      if (not defined?(@@last_scraper_class) or @@last_scraper_class.nil?)
        raise "Cannot initialize the scraper as none was loaded successfully."
      else
        logger.debug("About to instantiate scraper class: #{@@last_scraper_class.name}\n")
        scraper = @@last_scraper_class.new()
        scraper.logger = logger
        scraper.options = options
      end
     
      return scraper
    end # init_scraper
  end # Scraper
end # module Bankjob