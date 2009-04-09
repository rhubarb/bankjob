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
    # Returns the statement's start date.
    # The +from_date+ is taken from the date of the last transaction in the statement
    #
    def from_date()
      return nil if @transactions.empty?
      @transactions.last.date
    end

    ##
    # Returns the statement's end date.
    # The +to_date+ is taken from the date of the first transaction in the statement
    #
    def to_date()
      return nil if @transactions.empty?
      @transactions.first.date
    end

    ##
    # Returns the closing balance by looking at the
    # new balance of the first transaction.
    # If there are no transactions, +nil+ is returned.
    #
    def closing_balance()
      return nil if @closing_balance.nil? and @transactions.empty?
      @closing_balance ||= @transactions.first.new_balance
    end

    ##
    # Returns the closing available balance by looking at the
    # new balance of the first transaction.
    # If there are no transactions, +nil+ is returned.
    # Note that this is the same value returned as +closing_balance+.
    #
    def closing_available()
      return nil if @closing_available.nil? and @transactions.empty?
      @closing_available ||= @transactions.first.new_balance
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