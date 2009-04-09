
require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that BpiScraper extends

include Bankjob        # access the namespace of Bankjob

##
# BpiScraper is a scraper tailored to the BPI bank in Portugal (www.bpinet.pt).
# It takes advantage of the BaseScraper to create the mechanize agent,
# then followins the basic recipe there of first loading the tranasctions page
# then parsing it.
#
# In addition to actually working for the BPI online banking, this class serves
# as an example of how to build your own scraper.
#
# BpiScraper expects the user name and password to be passed on the command line
# using -scraper_args "user password" (with a space between them).
#
class BpiScraper < BaseScraper

  currency  "EUR" # Set the currency as euros
  decimal   ","    # BPI statements use commas as separators - this is used by the real_amount method
  account_number "1234567" # override this with a real accoun number
  account_type Statement::CHECKING # this is the default anyway

  # This rule detects ATM withdrawals and modifies
  # the description and sets the the type
  transaction_rule do |tx|
    if (tx.real_amount < 0)
      if tx.raw_description =~ /LEV.*ATM ELEC\s+\d+\/\d+\s+/i
        tx.description = "Multibanco withdrawal at #{$'}"
        tx.type = Transaction::ATM
      end
    end
  end

  # This rule detects checque payments and modifies the description
  # and sets the type
  transaction_rule do |tx|
    if tx.raw_description =~ /CHEQUE\s+(\d+)/i
      cheque_number = $+   # $+ holds the last group of the match which is (\d+)
      # change the description but append $' in case there was trailing text after the cheque no
      tx.description = "Cheque ##{cheque_number} withdrawn #{$'}"
      tx.type = Transaction::CHECK
      tx.check_number = cheque_number
    end
  end

  # This rule goes last and sets the description of transactions 
  # that haven't had their description to the raw description after
  # changing the words to have capital letters only on the first word.
  # (Note that +description+ will default to being the same as +raw_description+
  #  anyway - this rule is only for making the all uppercase output less ugly)
  # The payee is also fixed in this way
  transaction_rule(-999) do |tx|
    if (tx.description == tx.raw_description)
      tx.description = Bankjob.capitalize_words(tx.raw_description)
    end
  end

  # Some constants for the URLs and main elements in the BPI bank app
  LOGIN_URL = 'https://www.bpinet.pt/'
  TRANSACTIONS_URL = 'https://www.bpinet.pt/areaInf/consultas/Movimentos/Movimentos.asp'

  ##
  # Uses the mechanize web +agent+ to fetch the page holding the most recent
  # bank transactions and returns it.
  # This overrides (implements) +fetch_transactions_page+ in BaseScraper
  #
  def fetch_transactions_page(agent)
    login(agent)
    logger.info("Logged in, now navigating to transactions on #{TRANSACTIONS_URL}.")
    transactions_page = agent.get(TRANSACTIONS_URL)
    if (transactions_page.nil?)
      raise "BPI Scraper failed to load the transactions page at #{TRANSACTIONS_URL}"
    end
    return transactions_page
  end

  
  ##
  # Parses the BPI page listing about a weeks worth of transactions
  # and creates a Transaction for each one, putting them together
  # in a Statement.
  # Overrides (implements) +parse_transactions_page+ in BaseScraper.
  #
  def parse_transactions_page(transactions_page)
    begin
      statement = create_statement

      # Find the closing balance avaliable and accountable
      # Get from this:
      #    <td valign="middle" width="135" ALIGN="left" class="TextoAzulBold">Saldo Disponível:</td>
      #    <td valign="middle" width="110" ALIGN="right">1.751,31&nbsp;EUR</td>
      # to 1751,31
      available_cell = (transactions_page/"td").select { |ele| ele.inner_text =~ /^Saldo Dispon/ }.first.next_sibling
      statement.closing_available = available_cell.inner_text.scan(/[\d.,]+/)[0].gsub(/\./,"")
      account_balance_cell = (transactions_page/"td").select { |ele| ele.inner_text =~ /^Saldo Contab/ }.first.next_sibling
      statement.closing_balance = account_balance_cell.inner_text.scan(/[\d.,]+/)[0].gsub(/\./,"")

      transactions = []

      # find the first header with the CSS class "Laranja" as this will be the first
      # header in the transactions table
      header = (transactions_page/"td.Laranja").first

      # the table element is the grandparent element of this header (the row is the parent)
      table = header.parent.parent 

      # each row with the valign attribute set to "top" holds a transaction
      rows = (table/"tr[@valign=top]")
      rows.each do |row|
        transaction = create_transaction # use the support method because it sets the separator

        # collect all of the table cells' inner html in an array (stripping leading/trailing spaces)
        data = (row/"td").collect{ |cell| cell.inner_html.strip }

        # the first (0th) column holds the date 
        transaction.date = data[0]

        # the 2nd column holds the value date - but it's often empty 
        # in which case we set it to nil
        vdate = data[1]
        if vdate.nil? or vdate.length == 0 or vdate.strip == "&nbsp;"
          transaction.value_date = nil
        else
          transaction.value_date = vdate
        end

        # the transaction raw_description is in the 3rd column
        transaction.raw_description = data[2]

        # the 4th column holds the transaction amount (with comma as decimal place)
        transaction.amount = data[3]

        # the new balance is in the last column
        transaction.new_balance=data[4]

        # add thew new transaction to the array
        transactions << transaction
        #	break if $debug
      end
    rescue => exception
      msg = "Failed to parse the transactions page at due to exception: #{exception.message}\nCheck your user name and password."
      logger.fatal(msg);
      logger.debug(exception)
      logger.debug("Failed parsing transactions page:")
      logger.debug("--------------------------------")
      logger.debug(transactions_page) #.body
      logger.debug("--------------------------------")
      abort(msg)
    end

    # set the transactions on the statement
    statement.transactions = transactions
    return statement
  end

  ##
  # Logs into the BPI banking app by finding the form
  # setting the name and password and submitting it then
  # waits a bit.
  #
  def login(agent)
    logger.info("Logging in to #{LOGIN_URL}.")
    if (scraper_args)
      username, password = *scraper_args
    end
    raise "Login failed for BPI Scraper - pass user name and password using -scraper_args \"user <space> pass\"" unless (username and password)

    # navigate to the login page
    login_page = agent.get(LOGIN_URL)

    # find login form - it's called 'signOn' - fill it out and submit it
    form  = login_page.form('signOn')

    # username and password are taken from the commandline args, set them
    # on USERID and PASSWORD which are the element names that the web page
    # form uses to identify the form fields
    form.USERID = username
    form.PASSWORD = password

    # submit the form - same as the user hitting the Login button
    agent.submit(form)
    sleep 3  # wait while the login takes effect
  end
end # class BpiScraper


