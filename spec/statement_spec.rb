require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
#require File.expand_path(File.dirname(__FILE__) + '/../lib/bankjob.rb')
 
include Bankjob

# Test the Statement merging in particular
describe Statement do
  before(:each) do

    @tx1 = Transaction.new(",")
    @tx1.date = "20080730000000"
    @tx1.value_date = "20080731145906"
    @tx1.raw_description = "1 Stamp duty 001"
    @tx1.amount = "-2,40"
    @tx1.new_balance = "1.087,43"


    @tx2 = Transaction.new(",")
    @tx2.date = "0080729000000"
    @tx2.value_date = "20080731145906"
    @tx2.raw_description =  "2 Interest payment 001"
    @tx2.amount = "-59,94"
    @tx2.new_balance = "1.089,83"


    @tx3 = Transaction.new(",")
    @tx3.date = "20080208000000"
    @tx3.value_date = "20080731145906"
    @tx3.raw_description =  "3 Load payment 001"
    @tx3.amount = "-256,13"
    @tx3.new_balance = "1.149,77"


    @tx4 = Transaction.new(",")
    @tx4.date = "20080207000000"
    @tx4.value_date = "20080731145906"
    @tx4.raw_description =  "4 Transfer to bank 2"
    @tx4.amount = "-1.000,00"
    @tx4.new_balance = "1.405,90"


    @tx5 = Transaction.new(",")
    @tx5.date = "20080209000000"
    @tx5.value_date = "20080731145906"
    @tx5.raw_description =  "5 Internet payment 838"
    @tx5.amount = "-32,07"
    @tx5.new_balance = "1.405,90"

    # the lot
    @s12345 = Statement.new
    @s12345.transactions = [ @tx1.dup, @tx2.dup, @tx3.dup, @tx4.dup, @tx5.dup]

    # first 2
    @s12 = Statement.new
    @s12.transactions = [ @tx1.dup, @tx2.dup]

    # middle 1
    @s3 = Statement.new
    @s3.transactions = [ @tx3.dup]

    # last 2
    @s45 = Statement.new
    @s45.transactions = [ @tx4.dup, @tx5.dup]
    
    # first 3
    @s123 = Statement.new
    @s123.transactions = [ @tx1.dup, @tx2.dup, @tx3.dup]

    # last 4, overlaps with 23 of s123
    @s2345 = Statement.new
    @s2345.transactions = [ @tx2.dup, @tx3.dup, @tx4.dup, @tx5.dup]

    # 2nd and last - overlaps non-contiguously with s123
    @s25 = Statement.new
    @s25.transactions = [ @tx2.dup, @tx5.dup]
    
  end

  it "should merge consecutive satements properly" do
    @s123.merge(@s45).should == @s12345
  end

  it "should merge overlapping statments properly" do
    #@s123.merge(@s2345).transactions.each { |tx| print "#{tx.to_s}, "}
    @s123.merge(@s2345).should == @s12345
  end

  it "should merge a statement with a duplicate of itself without changing it" do
    @s123.merge(@s123.dup).should == @s123
  end


  it "should merge non-contiguous with an error" do
    m =  @s123.merge(@s25)
    m.transactions.each { |tx| print "#{tx.to_s}, "}
  end

  it "should read back a satement from csv as it was written" do
    csv = @s123.to_csv
    statement = Statement.new()
    statement.from_csv(csv, ",")
    statement.should == @s123
  end

  it "should read back and merge a statement with itself without change" do
    csv = @s123.to_csv
    statement = Statement.new()
    statement.from_csv(csv, ",")
    m = @s123.merge(statement)
    m.should == @s123
  end

  it "should write, read, merge and write a statement without changing it" do
    csv = @s123.to_csv
    statement = Statement.new()
    m = @s123.merge(statement)
    m_csv = m.to_csv
    m_csv.should == csv
  end
end

