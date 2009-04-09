require 'rubygems'
require 'mechanize'
require 'hpricot'
require 'bankjob'

# Later versions of Mechanize no longer use Hpricot by default
# but have an attribute we can set to use it
begin
  WWW::Mechanize.html_parser = Hpricot
rescue NoMethodError
end

include Bankjob

  ##
  # BaseScraper is a specific example of a Bankjob Scraper that can be used as a base
  # class for scrapers that follow a typical pattern.
  # 
  # In fact, it does not add much functionality and you could just as readily subclass
  # the Scraper class as this class, but here is what it does add:
  # *+scraper_args+ attribute holds the array of args specified by the -scraper_args command line option
  # *+scrape_statement+ is implemented to use the --input command line option to specify a file for input
  #                      so that you can save a web-page to a file for debugging
  # *+scrape_statement+ instantiates a Mechanize agent and delegates to two other 
  #                     simple methods that must be overridden in a subclass.
  # 
  # Specifically +scrape_statement+ passes the Mechanize agent to +fetch_transactions_page+
  # then passes the resulting page to +parse_transactions_page. Subclasses must implement these two methods.
  # See the documentation for these methods for more details on how to implement them.
  # Note that failure to override either method will result in an exception.
  #
  class BaseScraper < Scraper

    # +scraper_args+ holds the array of arguments specified on the command line with
    # the -scraper_args option. It is not used here, but it is set in the scrape_statement
    # method so that you can access it in your subclass.
    attr_accessor :scraper_args

    # This rule goes last and sets the type of any transactions
    # that are still set to OTHER to be the generic CREDIT or DEBIT
    # depending on the real amount of the transaction
    # +prioirity+ set to -999 to ensure it's last
    transaction_rule(-999) do |tx|
      if (tx.type == Transaction::OTHER)
        if tx.real_amount > 0
          tx.type = Transaction::CREDIT
        elsif tx.real_amount < 0
          tx.type = Transaction::DEBIT
        end
        # else leave it as OTHER if it's exactly zero
      end
    end

    ##
    # Override +fetch_transactions_page+ to use the mechanize +agent+ to
    # load the page holding your bank statement on your online banking website.
    # By using agent.get(url) to fetch the page, the returned page will be
    # an Hpricot document ready for parsing.
    #
    # Typically you will need to log-in using a form on a login page first.
    # Your implementation may look something like this:
    # 
    #   # My online banking app has a logon page with a standard HTML form.
    #   # by looking at the source of the page I see that the form is named
    #   # 'MyLoginFormName' and the two text fields for user name and password
    #   # are called 'USERNAME' and 'PASSWORD' respectively.
    #   login_page = agent.get("http://mybankapp.com/login.html")
    #   form  = login_page.forms.name('MyLoginFormName').first
    #   # Mechanize automatically makes constants for the form elements based on their names.
    #   form.USERNAME = "me"
    #   form.PASSWORD = "foo"
    #   agent.submit(form)
    #   sleep 3  #wait while the login takes effect
    #
    #   # Now that I've logged in and waited a bit, navigate to the page that lists
    #   # my recent transactions and return it
    #   return agent.get("http://mybankapp.com/latesttransactions.html")
    #
    def fetch_transactions_page(agent)
      raise "You must override fetch_transactions_page in your subclass of BaseScraper " +
            "or just subclass Scraper instead and override scrape_statement"
    end

    ##
    # Override +parse_transactions_page+ to take the Hpricot document passed in
    # as +page+, parse it using Hpricot directives, and create a Statement object
    # holding a set of Transaction objects for it.
    #
    def parse_transactions_page(page)
      raise "You must override parse_transactions_page in your subclass of BaseScraper " +
            "or just subclass Scraper instead and override scrape_statement"
    end

    ##
    # Implements the one essential method of a scraper +scrape_statement+
    # by calling +fetch_transactions_page+ to get a web page holding a bank
    # statement followed by a call to +parse_transactions_page+ that returns
    # the +Statement+ object.
    #
    # Do not override this method in a subclass. (If you want to override it
    # you should be subclassing Scraper instead of this class)
    #
    # If the --input argument has been used to specify and input html file to
    # use, this will be parsed directly instead of calling +fetch_transaction_page+.
    # This allows for easy debugging without slow web-scraping (simply view
    # the page in a regular browser and use Save Page As to save a local copy
    # of it, then specify thiswith the --input command-line arg)
    #
    # +args+ holds the array of arguments specified on the command line with 
    # the -scraper_args option. It is not used here, but it is set on an
    # attribute called scraper_args and is thus accessible in your subclass.
    #
    def scrape_statement(args)
      self.scraper_args = args
      if (not options.input.nil?) then
        # used for debugging - load the page from a file instead of the web
        logger.debug("Reading debug input html from #{options.input} instead of scraping the real website.")
        page = Hpricot(open(options.input))
      else
        # not debugging use the actual scraper
        # First create a mechanize agent: a sort of pretend web browser
        agent = WWW::Mechanize.new
        agent.user_agent_alias = 'Windows IE 6' # pretend that we're IE 6.0
        
        page = fetch_transactions_page(agent)
      end
      raise "BaseScraper failed to load the transactions page" if page.nil?
      # Now that we've feteched the page, parse it to get a statement
      statement = parse_transactions_page(page)
      return statement
    end
  end # BaseScraper

