require 'rubygems'
require 'builder'
require 'fastercsv'
require 'bankjob'

module Bankjob

  ##
  # A Statement object represents a bank statement and is generally the result of running a Bankjob scraper.
  # The Statement holds an array of Transaction objects and specifies the closing balance and the currency in use.
  #
  # A Scraper will create a Statement by scraping web pages in an online banking site.
  # The Statement can then be stored as a file in CSV (Comma Separated Values) format
  # using +to_csv+ or in OFX (Open Financial eXchange http://www.ofx.net) format
  # using +to_ofx+.
  #
  # One special ability of Statement is the ability to merge with an existing statement,
  # automatically eliminating overlapping transactions.
  # This means that when writing subsequent statements to the same CSV file
  # <em>(note well: CSV only)</em> a continous transaction record can be built up
  # over a long period.
  #
  class Statement

    # OFX value for the ACCTTYPE of a checking account
    CHECKING   = "CHECKING"

    # OFX value for the ACCTTYPE of a savings account
    SAVINGS    = "SAVINGS"

    # OFX value for the ACCTTYPE of a money market account
    MONEYMRKT  = "MONEYMRKT"

    # OFX value for the ACCTTYPE of a loan account
    CREDITLINE = "CREDITLINE"

    # the account balance after the last transaction in the statement
    # Translates to the OFX element BALAMT in LEDGERBAL
    attr_accessor :closing_balance

    # the avaliable funds in the account after the last transaction in the statement (generally the same as closing_balance)
    # Translates to the OFX element BALAMT in AVAILBAL
    attr_accessor :closing_available

    # the array of Transaction objects that comprise the statement
    attr_accessor :transactions

    # the three-letter currency symbol generated into the OFX output (defaults to EUR)
    # This is passed into the initializer (usually by the Scraper - see Scraper#currency)
    attr_reader :currency 

    # the identifier of the bank - a 1-9 char string (may be empty)
    # Translates to the OFX element BANKID
    attr_accessor :bank_id

    # the account number of the statement - a 1-22 char string that must be passed
    # into the initalizer of the Statement
    # Translates to the OFX element ACCTID
    attr_accessor :account_number

    # the type of bank account the statement is for
    # Tranlsates to the OFX type ACCTTYPE and must be one of
    # * CHECKING
    # * SAVINGS
    # * MONEYMRKT
    # * CREDITLINE
    # Use a constant to set this - defaults to CHECKING
    attr_accessor :account_type

    # the last date of the period the statement covers
    # Translates to the OFX element DTEND
    attr_accessor :to_date

    # the first date of the period the statement covers
    # Translates to the OFX element DTSTART
    attr_accessor :from_date

    ##
    # Creates a new empty Statement with no transactions.
    # The +account_number+ must be specified as a 1-22 character string.
    # The specified +currency+ defaults to EUR if nothing is passed in.
    #
    def initialize(account_number, currency = "EUR")
      @account_number = account_number
      @currency = currency
      @transactions = []
      @account_type = CHECKING
      @closing_balance = nil
      @closing_available = nil
    end
    
    ##
    # Appends a new Transaction to the end of this Statement
    #
    def add_transaction(transaction)
      @transactions << transaction
    end

    ##
    # Overrides == to allow comparison of Statement objects.
    # Two Statements are considered equal (that is, ==) if
    # and only iff they have the same values for:
    # * +to_date+
    # * +from_date+
    # * +closing_balance+
    # * +closing_available+
    # * each and every transaction.
    # Note that the transactions are compared with Transaction.==
    #
    def ==(other) # :nodoc:
      if other.kind_of?(Statement) 
        return (from_date == other.from_date and
            to_date == other.to_date and
            closing_balance == other.closing_balance and
            closing_available == other.closing_available and
            transactions == other.transactions)
      end
      return false
    end
   
    ##
    # Merges the transactions of +other+ into the transactions of this statement
    # and returns the resulting array of transactions
    # Raises an exception if the two statements overlap in a discontiguous fashion.
    #
    def merge_transactions(other)
      if (other.kind_of?(Statement))
        union = transactions | other.transactions # the set union of both
        # now check that the union contains all of the originals, otherwise
        # we have merged some sort of non-contiguous range
        raise "Failed to merge transactions properly." unless union.first(@transactions.length) == @transactions
        return union
      end
    end

    ##
    # Merges the transactions of +other+ into the transactions of this statement
    # and returns the result.
    # Neither statement is changed. See #merge! if you want to modify the statement.
    # Raises an exception if the two statements overlap in a discontiguous fashion.
    #
    def merge(other)
      union = merge_transactions(other)
      merged = self.dup
      merged.closing_balance = nil
      merged.closing_available = nil
      merged.transactions = union
      return merged
    end

    ##
    # Merges the transactions of +other+ into the transactions of this statement.
    # Causes this statement to be changed. See #merge for details.
    #
    def merge!(other)
      @closing_balance = nil
      @closing_available = nil
      @transactions = merge_transactions(other)
    end

    ##
    # Generates a CSV (comma separated values) string with a single
    # row for each transaction.
    # Note that no header row is generated as it would make it
    # difficult to concatenate and merge subsequent CSV strings
    # (but we should consider it as a user option in the future)
    #
    def to_csv
      buf = ""
      transactions.each do |transaction|
        buf << transaction.to_csv
      end
      return buf
    end

    ##
    # Generates a string for use as a header in a CSV file for a statement.
    #
    # Delegates to Transaction#csv_header
    #
    def self.csv_header
      return Transaction.csv_header
    end

    ##
    # Reads in transactions from a CSV file or string specified by +source+
    # and adds them to this statement.
    # 
    # Uses a simple (dumb) heuristic to determine if the +source+ is a file
    # or a string: if it contains a comma (,) then it is a string
    # otherwise it is treated as a file path.
    #
    def from_csv(source, decimal = ".")
      if (source =~ /,/)
        # assume source is a string
        FasterCSV.parse(source) do |row|
          add_transaction(Transaction.from_csv(row, decimal))
        end
      else
        # assume source is a filepath
        FasterCSV.foreach(source) do |row|
          add_transaction(Transaction.from_csv(row, decimal))
        end
      end
    end

    ##
    # Generates an XML string adhering to the OFX standard
    # (see Open Financial eXchange http://www.ofx.net)
    # representing a single bank statement holding a list
    # of transactions.
    # The XML for the individual transactions is generated
    # by the Transaction class itself.
    #
    # The OFX 2 schema for a statement response (STMTRS) is:
    #
    #  <xsd:complexType name="StatementResponse">
    #    <xsd:annotation>
    #      <xsd:documentation>
    #        The OFX element "STMTRS" is of type "StatementResponse"
    #      </xsd:documentation>
    #    </xsd:annotation>
    #
    #    <xsd:sequence>
    #      <xsd:element name="CURDEF" type="ofx:CurrencyEnum"/>
    #      <xsd:element name="BANKACCTFROM" type="ofx:BankAccount"/>
    #      <xsd:element name="BANKTRANLIST" type="ofx:BankTransactionList" minOccurs="0"/>
    #      <xsd:element name="LEDGERBAL" type="ofx:LedgerBalance"/>
    #      <xsd:element name="AVAILBAL" type="ofx:AvailableBalance" minOccurs="0"/>
    #      <xsd:element name="BALLIST" type="ofx:BalanceList" minOccurs="0"/>
    #      <xsd:element name="MKTGINFO" type="ofx:InfoType" minOccurs="0"/>
    #    </xsd:sequence>
    #  </xsd:complexType>
    #
    # Where the BANKTRANLIST (Bank Transaction List) is defined as:
    #
    #  <xsd:complexType name="BankTransactionList">
    #    <xsd:annotation>
    #      <xsd:documentation>
    #        The OFX element "BANKTRANLIST" is of type "BankTransactionList"
    #      </xsd:documentation>
    #    </xsd:annotation>
    #    <xsd:sequence>
    #      <xsd:element name="DTSTART" type="ofx:DateTimeType"/>
    #      <xsd:element name="DTEND" type="ofx:DateTimeType"/>
    #      <xsd:element name="STMTTRN" type="ofx:StatementTransaction" minOccurs="0" maxOccurs="unbounded"/>
    #    </xsd:sequence>
    #  </xsd:complexType>
    #
    # And this is the definition of the type BankAccount.
    #
    #  <xsd:complexType name="BankAccount">
		#    <xsd:annotation>
		#      <xsd:documentation>
    #        The OFX elements BANKACCTFROM and BANKACCTTO are of type "BankAccount"
    #      </xsd:documentation>
		#    </xsd:annotation>
		#    <xsd:complexContent>
		#      <xsd:extension base="ofx:AbstractAccount">
    #        <xsd:sequence>
    #          <xsd:element name="BANKID" type="ofx:BankIdType"/>
    #          <xsd:element name="BRANCHID" type="ofx:AccountIdType" minOccurs="0"/>
    #          <xsd:element name="ACCTID" type="ofx:AccountIdType"/>
    #          <xsd:element name="ACCTTYPE" type="ofx:AccountEnum"/>
    #          <xsd:element name="ACCTKEY" type="ofx:AccountIdType" minOccurs="0"/>
    #        </xsd:sequence>
    #      </xsd:extension>
    #    </xsd:complexContent>
    #  </xsd:complexType>
    #
    # The to_ofx method will only generate the essential elements which are 
    # * BANKID - the bank identifier (a 1-9 char string - may be empty)
    # * ACCTID - the account number (a 1-22 char string - may not be empty!)
    # * ACCTTYPE - the type of account - must be one of:
    #              "CHECKING", "SAVINGS", "MONEYMRKT", "CREDITLINE"
    #
    # (See Transaction for a definition of STMTTRN)
    #
    def to_ofx
      buf = ""
      # Use Builder to generate XML. Builder works by catching missing_method
      # calls and generating an XML element with the name of the missing method,
      # nesting according to the nesting of the calls and using arguments for content
      x = Builder::XmlMarkup.new(:target => buf, :indent => 2)
      x.OFX {
        x.BANKMSGSRSV1 { #Bank Message Response
          x.STMTTRNRS {		#Statement-transaction aggregate response
            x.STMTRS {		#Statement response
              x.CURDEF currency	#Currency
              x.BANKACCTFROM {
                x.BANKID bank_id # bank identifier
                x.ACCTID account_number
                x.ACCTTYPE account_type # acct type: checking/savings/...
              }
              x.BANKTRANLIST {	#Transactions
                x.DTSTART Bankjob.date_time_to_ofx(from_date)
                x.DTEND Bankjob.date_time_to_ofx(to_date)
                transactions.each { |transaction|
                  buf << transaction.to_ofx
                }
              }
              x.LEDGERBAL {	# the final balance at the end of the statement
                x.BALAMT closing_balance # balance amount
                x.DTASOF Bankjob.date_time_to_ofx(to_date)		# balance date
              }
              x.AVAILBAL {	# the final Available balance
                x.BALAMT closing_available
                x.DTASOF Bankjob.date_time_to_ofx(to_date)
              }
            }
          }
        }
      }
      return buf
    end
    
    ONE_MINUTE = 60
    ELEVEN_59_PM = 23 * 60 * 60 + 59 * 60  # seconds at 23:59
    MIDDAY = 12 * 60 * 60

    ##
    # Finishes the statement after scraping in two ways depending on the information
    # that the scraper was able to obtain. Optionally have your scraper class call
    # this after scraping is finished.
    #
    # This method:
    # 
    # 1. Sets the closing balance and available_balance and the to_ and from_dates
    #    by using the first and last transactions in the list. Which transaction is
    #    used depends on whether +most_recent_first+ is true or false.
    #    The scraper may just set these directly in which case this may not be necessary.
    #
    # 2. If +fake_times+ is true time-stamps are invented and added to the transaction
    #    date attributes. This is useful if the website beings scraped shows dates, but
    #    not times, but has transactions listed in chronoligical arder. 
    #    Without this process, the ofx generated has no proper no indication of the order of
    #    transactions that occurred in the same day other than the order in the statement
    #    and this may be ignored by the client. (Specifically, Wesabe will reorder transactions
    #    in the same day if they all appear to occur at the same time).
    #    
    #    Note that the algorithm to set the fake times is a little tricky. Assuming
    #    the transactionsa are most-recent-first, the first last transaction on each 
    #    day is set at 11:59pm each transaction prior to that is one minute earlier.
    #    
    #    But for the first transactions in the statement, the first is set at a few
    #    minutes after midnight, then we count backward. (The actual number of minutes
    #    is based on the number of transactions + 1 to be sure it doesnt pass midnight)
    #    
    #    This is crucial because transactions for a given day will often span 2 or more
    #    statement. By starting just after midnight and going back to just before midnight
    #    we reduce the chance of overlap.
    #
    #    If the to-date is the same as the from-date for a transaction, then we start at
    #    midday, so that prior and subsequent statements don't overlap.
    #
    #   This simple algorithm basically guarantees no overlaps so long as:
    #   i.  The number of transactions is small compared to the number of minutes in a day
    #   ii. A single day will not span more than 3 statements
    #
    #   If the statement is most-recent-last (+most_recent_first = false+) the same
    #   algorithm is applied, only in reverse
    #
    def finish(most_recent_first, fake_times=false)
      if !@transactions.empty? then
        # if the user hasn't set the balances, set them to the first or last
        # transaction balance depending on the order
        if most_recent_first then
          @closing_balance ||= transactions.first.new_balance
          @closing_available ||= transactions.first.new_balance
          @to_date ||= transactions.first.date
          @from_date ||= transactions.last.date
        else
          @closing_balance ||= transactions.last.new_balance
          @closing_available ||= transactions.last.new_balance
          @to_date ||= transactions.last.date
          @from_date ||= transactions.first.date
        end

        if fake_times and to_date.hour == 0 then
          # the statement was unable to scrape times to go with the dates, but the
          # client (say wesabe) will get the transaction order wrong if there are no
          # times, so here we add times that order the transactions according to the
          # order of the array of transactions

          # the delta is 1 minute forward or backward fr
          if to_date == from_date then
            # all of the statement's transactions occur in the same day - to try to
            # avoid overlap with subsequent or previous transacitons we group order them
            # from 11am onward
            seconds = MIDDAY
          else
            seconds = (transactions.length + 1) * 60
          end

          if most_recent_first then
            yday = transactions.first.date.yday
            start = 0
            delta = 1
            finish = transactions.length
          else
            yday = transactions.last.date.yday
            start = transactions.length - 1
            finish = -1
            delta = -1
          end

          i = start
          until i == finish
            tx = transactions[i]
            if tx.date.yday != yday
              # starting a new day, begin the countdown from 23:59 again
              yday = tx.date.yday
              seconds = ELEVEN_59_PM
            end
            tx.date += seconds unless tx.date.hour > 0
            seconds -= ONE_MINUTE
            i += delta
          end
        end
      end
    end

    def to_s
      buf = "#{self.class}: close_bal = #{closing_balance}, avail = #{closing_available}, curr = #{currency}, transactions:"
      transactions.each do |tx|
        buf << "\n\t\t#{tx.to_s}"
      end
      buf << "\n---\n"
      return buf
    end
  end # class Statement
end # module
