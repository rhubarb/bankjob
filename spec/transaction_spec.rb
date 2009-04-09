require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'bankjob.rb'
include Bankjob

describe Transaction do
  before(:each) do
    @tx1 = Transaction.new()
    @tx1.date = "30-7-2008"
    @tx1.value_date = "20080731145906" 
    @tx1.raw_description = "Some tax thing 10493"
    @tx1.amount = "-2,40"
    @tx1.new_balance = "1.087,43"

    @tx1_copy = Transaction.new()
    @tx1_copy.date = "30-7-2008"
    @tx1_copy.value_date = "20080731145906" 
    @tx1_copy.raw_description = "Some tax thing 10493"
    @tx1_copy.amount = "-2,40"
    @tx1_copy.new_balance = "1.087,43"
  
    @tx1_dup = @tx1.dup

    @tx2 = Transaction.new()
    @tx2.date = "0080729000000"
    @tx2.value_date = "20080731145906" 
    @tx2.raw_description = "Interest payment"
    @tx2.amount = "-59,94"
    @tx2.new_balance = "1.089,83"
  end

  it "should generate the same ofx_id as its copy" do
    puts "tx1: #{@tx1.to_s}\n-----"
    puts "tx1_copy: #{@tx1.to_s}"
    @tx1.ofx_id.should == @tx1_copy.ofx_id
    puts "#{@tx1.ofx_id} == #{@tx1_copy.ofx_id}"
  end

  it "should generate the same ofx_id as its duplicate" do
    @tx1.ofx_id.should == @tx1_dup.ofx_id
  end


  it "should be == to its duplicate" do
    @tx1.should == @tx1_dup
  end

  it "should be == to its identical copy" do
    @tx1.should == @tx1_copy
  end

  it "should not == a different transaction" do
    @tx1.should_not == @tx2
  end

  it "should be eql to its duplicate (necessary for merging)"  do
    @tx1.should eql(@tx1_dup)
  end

  it "should not be equal to its duplicate" do
    @tx1.should_not equal(@tx1_dup)
  end

  it "should be === to its duplicate" do
    @tx1.should === @tx1_dup
  end

  it "should have the same hash as its duplicate" do
    @tx1.hash.should == @tx1_dup.hash
  end

  it "should convert 1,000,000.32 to 1000000.32 when decimal separator is ." do
   Bankjob.string_to_float("1,000,000.32", ".").should == 1000000.32
  end

  it "should convert 1.000.000,32 to 1000000.32 when decimal separator is ," do
   Bankjob.string_to_float("1.000.000,32", ",").should == 1000000.32
  end

end

