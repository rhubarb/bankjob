
require 'rubygems'
require 'builder'
require 'digest/md5'
require 'bankjob.rb'

module Bankjob

  ##
  # A Transaction object represents a transaction in a bank account (a withdrawal, deposit,
  # transfer, etc) and is generally the result of running a Bankjob scraper.
  #
  # A Scraper will create Transactions while scraping web pages in an online banking site.
  # These Transactions will be collected in a Statement object which will then be written
  # to a file.
  #
  # A Transaction object knows how to write itself as a record in a CSV
  # (Comma Separated Values) file using +to_csv+ or as an XML element in an
  # OFX (Open Financial eXchange http://www.ofx.net) file using +to_ofx+
  #
  class Transaction

    # OFX transaction type for Generic credit
    CREDIT      = "CREDIT"

    # OFX transaction type for Generic debit
    DEBIT       = "DEBIT"

    # OFX transaction type for Interest earned or paid. (Depends on signage of amount)
    INT         = "INT"

    # OFX transaction type for Dividend
    DIV         = "DIV"

    # OFX transaction type for FI fee
    FEE         = "FEE"

    # OFX transaction type for Service charge
    SRVCHG      = "SRVCHG"

    # OFX transaction type for Deposit
    DEP         = "DEP"

    # OFX transaction type for ATM debit or credit. (Depends on signage of amount)
    ATM         = "ATM"

    # OFX transaction type for Point of sale debit or credit. (Depends on signage of amount)
    POS         = "POS"

    # OFX transaction type for Transfer
    XFER        = "XFER"

    # OFX transaction type for Check
    CHECK       = "CHECK"

    # OFX transaction type for Electronic payment
    PAYMENT     = "PAYMENT"

    # OFX transaction type for Cash withdrawal
    CASH        = "CASH"

    # OFX transaction type for Direct deposit
    DIRECTDEP   = "DIRECTDEP"

    # OFX transaction type for Merchant initiated debit
    DIRECTDEBIT = "DIRECTDEBIT"

    # OFX transaction type for Repeating payment/standing order
    REPEATPMT   = "REPEATPMT"

    # OFX transaction type for Other
    OTHER       = "OTHER"

    # OFX type of the transaction (credit, debit, atm withdrawal, etc)
    # Translates to the OFX element TRNTYPE and according to the OFX 2.0.3 schema this can be one of
    # * CREDIT
    # * DEBIT
    # * INT
    # * DIV
    # * FEE
    # * SRVCHG
    # * DEP
    # * ATM
    # * POS
    # * XFER
    # * CHECK
    # * PAYMENT
    # * CASH
    # * DIRECTDEP
    # * DIRECTDEBIT
    # * REPEATPMT
    # * OTHER
    attr_accessor :type

    # date of the transaction
    # Translates to OFX element DTPOSTED
    attr_accessor :date

    # the date the value affects the account (e.g. funds become available)
    # Translates to OFX element DTUSER
    attr_accessor :value_date

    # description of the transaction
    # This description is typically set by taking the raw description and
    # applying rules. If it is not set explicitly it returns the same
    # value as +raw_description+
    # Translates to OFX element MEMO
    attr_accessor :description

    # the original format of the description as scraped from the bank site
    # This allows the raw information to be preserved when modifying the
    # +description+ with transaction rules (see Scraper#transaction_rule)
    # This does _not_ appear in the OFX output, only +description+ does.
    attr_accessor :raw_description

    # amount of the credit or debit (negative for debits)
    # Translates to OFX element TRNAMT
    attr_accessor :amount

    # account balance after the transaction
    # Not used in OFX but important for working out statement balances
    attr_accessor :new_balance

    # account balance after the transaction as a numeric Ruby Float
    # Not used in OFX but important for working out statement balances
    # in calculations (see #real_amount)
    attr_reader :real_new_balance

    # the generated unique id for this transaction in an OFX record
    # Translates to OFX element FITID this is generated if not set
    attr_accessor :ofx_id

    # the payee of an expenditure (ie a debit or transfer)
    # This is of type Payee and translates to complex OFX element PAYEE
    attr_accessor :payee

    # the cheque number of a cheque transaction
    # This is of type Payee and translates to OFX element CHECKNUM
    attr_accessor :check_number

    ##
    # the numeric real-number amount of the transaction.
    #
    # The transaction amount is typically a string and may hold commas for
    # 1000s or for decimal separators, making it unusable for mathematical
    # operations.
    #
    # This attribute returns the amount converted to a Ruby Float, which can
    # be used in operations like:
    # <tt>
    #   if (transaction.real_amount < 0)
    #     puts "It's a debit!"
    #   end
    #
    # The +real_amount+ attribute is calculated using the +decimal+ separator
    # passed into the constructor (defaults to ".")
    # See Scraper#decimal
    #
    # This attribute is not used in OFX.
    #
    attr_reader :real_amount

    ##
    # Creates a new Transaction with the specified attributes.
    #
    def initialize(decimal = ".")
      @ofx_id = nil
      @date = nil
      @value_date = nil
      @raw_description = nil
      @description = nil
      @amount = 0
      @new_balance = 0
      @decimal = decimal

      # Always create a Payee even if it doesn't get used - this ensures an empty
      # <PAYEE> element in the OFX output which is more correct and, for one thing,
      # stops Wesabe from adding UNKNOWN PAYEE to every transaction (even deposits)
      @payee = Payee.new()
      @check_number = nil
      @type = OTHER
    end
   
    def date=(raw_date_time)
      @date = Bankjob.create_date_time(raw_date_time)
    end

    def value_date=(raw_date_time)
      @value_date = Bankjob.create_date_time(raw_date_time)
    end

    ##
    # Creates a unique ID for the transaction for use in OFX documents, unless
    # one has already been set.
    # All OFX transactions need a unique identifier.
    #
    # Note that this is generated by creating an MD5 digest of the transaction
    # date, raw description, type, amount and new_balance. Which means that two
    # identical transactions will always produce the same +ofx_id+.
    # (This is important so that repeated scrapes of the same transaction value
    #  produce identical ofx_id values)
    #
    def ofx_id() 
      if @ofx_id.nil?
        text = "#{@date}:#{@raw_description}:#{@type}:#{@amount}:#{@new_balance}"
        @ofx_id= Digest::MD5.hexdigest(text)
      end
      return @ofx_id
    end

    ##
    # Returns the description, defaulting to the +raw_description+ if no
    # specific description has been set by the user.
    #
    def description()
      @description.nil? ? raw_description : @description
    end

    ##
    # Returns the Transaction amount attribute as a ruby Float after 
    # replacing the decimal separator with a . and stripping any other
    # separators.
    #
    def real_amount()
      Bankjob.string_to_float(amount, @decimal)
    end

    ##
    # Returns the new balance after the transaction as a ruby Float after
    # replacing the decimal separator with a . and stripping any other
    # separators.
    #
    def real_new_balance()
      Bankjob.string_to_float(new_balance, @decimal)
    end

    ##
    # Generates a string representing this Transaction as comma separated values
    # in the form:
    #
    # <tt>date, value_date, description, real_amount, real_new_balance, amount, new_balance, raw_description, ofx_id</tt>
    #
    def to_csv
      # if there's a payee, prepend their name to the description - otherwise skip it
      if (not payee.nil? and (not payee.name.nil?))
        desc = payee.name + " - " + description
      else
        desc = description
      end
      [Bankjob.date_time_to_csv(date), Bankjob.date_time_to_csv(value_date), desc, real_amount, real_new_balance, amount, new_balance, raw_description, ofx_id].to_csv
    end

    ##
    # Generates a string for use as a header in a CSV file for transactions.
    # This will produce the following string:
    #
    # <tt>date, value_date, description, real_amount, real_new_balance, amount, new_balance, raw_description, ofx_id</tt>
    #
    def self.csv_header
      %w{ Date Value-Date Description Amount New-Balance Raw-Amount Raw-New-Balance Raw-Description OFX-ID }.to_csv
    end

    ##
    # Creates a new Transaction from a string that defines a row in a CSV file.
    #
    # +csv_row+ must hold an array of values in precisely this order:
    #
    # <tt>date, value_date, description, real_amount, real_new_balance, amount, new_balance, raw_description, ofx_id</tt>
    #
    # <em>(The format should be the same as that produced by +to_csv+)</em>
    #
    def self.from_csv(csv_row, decimal)
      if (csv_row.length != 9)  # must have 9 cols
        csv_lines = csv_row.join("\n\t")
        msg = "Failed to create Transaction from csv row: \n\t#{csv_lines}\n"
        msg << " - 9 columns are required in the form: date, value_date, "
        msg << "description, real_amount, real_new_balance, amount, new_balance, "
        msg << "raw_description, ofx_id"
        raise msg
      end
      tx = Transaction.new(decimal)
      tx.date, tx.value_date, tx.description = csv_row[0..2]
      # skip real_amount and real_new_balance, they're read only and calculated
      tx.amount, tx.new_balance, tx.raw_description, tx.ofx_id = csv_row[5..8]
      return tx
    end

    ##
    # Generates an XML string adhering to the OFX standard
    # (see Open Financial Exchange http://www.ofx.net)
    # representing a single Transaction XML element.
    #
    # The OFX 2 schema defines a STMTTRN (SatementTransaction) as follows:
    #
    #  <xsd:complexType name="StatementTransaction">
    #    <xsd:annotation>
    #      <xsd:documentation>
    #        The OFX element "STMTTRN" is of type "StatementTransaction"
    #      </xsd:documentation>
    #    </xsd:annotation>
    #    <xsd:sequence>
    #      <xsd:element name="TRNTYPE" type="ofx:TransactionEnum"/>
    #      <xsd:element name="DTPOSTED" type="ofx:DateTimeType"/>
    #      <xsd:element name="DTUSER" type="ofx:DateTimeType" minOccurs="0"/>
    #      <xsd:element name="DTAVAIL" type="ofx:DateTimeType" minOccurs="0"/>
    #      <xsd:element name="TRNAMT" type="ofx:AmountType"/>
    #      <xsd:element name="FITID" type="ofx:FinancialInstitutionTransactionIdType"/>
    #      <xsd:sequence minOccurs="0">
    #        <xsd:element name="CORRECTFITID" type="ofx:FinancialInstitutionTransactionIdType"/>
    #        <xsd:element name="CORRECTACTION" type="ofx:CorrectiveActionEnum"/>
    #      </xsd:sequence>
    #      <xsd:element name="SRVRTID" type="ofx:ServerIdType" minOccurs="0"/>
    #      <xsd:element name="CHECKNUM" type="ofx:CheckNumberType" minOccurs="0"/>
    #      <xsd:element name="REFNUM" type="ofx:ReferenceNumberType" minOccurs="0"/>
    #      <xsd:element name="SIC" type="ofx:StandardIndustryCodeType" minOccurs="0"/>
    #      <xsd:element name="PAYEEID" type="ofx:PayeeIdType" minOccurs="0"/>
    #      <xsd:choice minOccurs="0">
    #        <xsd:element name="NAME" type="ofx:GenericNameType"/>
    #        <xsd:element name="PAYEE" type="ofx:Payee"/>
    #      </xsd:choice>
    #      <xsd:choice minOccurs="0">
    #        <xsd:element name="BANKACCTTO" type="ofx:BankAccount"/>
    #        <xsd:element name="CCACCTTO" type="ofx:CreditCardAccount"/>
    #      </xsd:choice>
    #      <xsd:element name="MEMO" type="ofx:MessageType" minOccurs="0"/>
    #      <xsd:choice minOccurs="0">
    #        <xsd:element name="CURRENCY" type="ofx:Currency"/>
    #        <xsd:element name="ORIGCURRENCY" type="ofx:Currency"/>
    #      </xsd:choice>
    #      <xsd:element name="INV401KSOURCE" type="ofx:Investment401kSourceEnum" minOccurs="0"/>
    #    </xsd:sequence>
    #  </xsd:complexType>
    #
    def to_ofx
      buf = ""
      # Set margin=5 to indent it nicely within the output from Statement.to_ofx
      x = Builder::XmlMarkup.new(:target => buf, :indent => 2, :margin=>5)
      x.STMTTRN {	# transaction statement
        x.TRNTYPE type
        x.DTPOSTED Bankjob.date_time_to_ofx(date)	#Date transaction was posted to account, [datetime] yyyymmdd or yyyymmddhhmmss
        x.TRNAMT amount	#Ammount of transaction [amount] can be , or . separated
        x.FITID ofx_id
        x.CHECKNUM check_number unless check_number.nil?
        buf << payee.to_ofx unless payee.nil?
        #x.NAME description
        x.MEMO description
      }
      return buf
    end
    
    ##
    # Produces a string representation of the transaction
    #
    def to_s
      "#{self.class} - ofx_id: #{@ofx_id}, date:#{@date}, raw description: #{@raw_description}, type: #{@type} amount: #{@amount}, new balance: #{@new_balance}"
    end

    ##
    # Overrides == to allow comparison of Transaction objects so that they can
    # be merged in Statements. See Statement#merge
    #
    def ==(other) #:nodoc:
      if other.kind_of?(Transaction)
        # sometimes the same date, when written and read back will not appear equal so convert to 
        # a canonical string first
        return (Bankjob.date_time_to_ofx(@date) == Bankjob.date_time_to_ofx(other.date) and
            # ignore value date - it may be updated between statements
            # (consider using ofx_id here later)
            @raw_description == other.raw_description and
            @amount == other.amount and
            @type == other.type and
            @new_balance == other.new_balance)
      end
    end

    #
    # Overrides eql? so that array union will work when merging statements
    #
    def eql?(other) #:nodoc:
      return self == other
    end

    ##
    # Overrides hash so that array union will work when merging statements
    #
    def hash() #:nodoc:
      prime = 31;
      result = 1;
      result = prime * result + @amount.to_i
      result = prime * result + @new_balance.to_i
      result = prime * result + (@date.nil? ? 0 : Bankjob.date_time_to_ofx(@date).hash);
      result = prime * result + (@raw_description.nil? ? 0 : @raw_description.hash);
      result = prime * result + (@type.nil? ? 0 : @type.hash);
      # don't use value date
      return result;
    end

  end # class Transaction
end # module

