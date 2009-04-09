
require 'rubygems'
require 'builder'
require 'digest/md5'

module Bankjob

  ##
  # A Payee object represents an entity in a in a bank Transaction that receives a payment.
  #
  # A Scraper will create Payees while scraping web pages in an online banking site.
  # In many cases Payees will not be distinguished in the online bank site in which case
  # rules will have to be applied to separate the Payees
  #
  # A Payee object knows how to write itself as a record in a CSV
  # (Comma Separated Values) file using +to_csv+ or as an XML element in an
  # OFX (Open Financial eXchange http://www.ofx.net) file using +to_ofx+
  #
  class Payee

    # name of the payee
    # Translates to OFX element NAME
    attr_accessor :name

    # address of the payee
    # Translates to OFX element ADDR1
    #-- TODO Consider ADDR2,3
    attr_accessor :address

    # city in which the payee is located
    # Translates to OFX element CITY
    attr_accessor :city

    # state in which the payee is located
    # Translates to OFX element STATE
    attr_accessor :state

    # post code or zip in which the payee is located
    # Translates to OFX element POSTALCODE
    attr_accessor :postalcode

    # country in which the payee is located
    # Translates to OFX element COUNTRY
    attr_accessor :country

    # phone number of the payee
    # Translates to OFX element PHONE
    attr_accessor :phone
   
    ##
    # Generates a string representing this Payee as a single string for use
    # in a comma separated values column
    #
    def to_csv
      name
    end
    
    ##
    # Generates an XML string adhering to the OFX standard
    # (see Open Financial Exchange http://www.ofx.net)
    # representing a single Payee XML element.
    #
    # The schema for the OFX produced is
    #
    #  <xsd:complexType name="Payee">
    #    <xsd:annotation>
    #      <xsd:documentation>
    #        The OFX element "PAYEE" is of type "Payee"
    #      </xsd:documentation>
    #    </xsd:annotation>
    #    <xsd:sequence>
    #      <xsd:element name="NAME" type="ofx:GenericNameType"/>
    #      <xsd:sequence>
    #        <xsd:element name="ADDR1" type="ofx:AddressType"/>
    #        <xsd:sequence minOccurs="0">
    #          <xsd:element name="ADDR2" type="ofx:AddressType"/>
    #          <xsd:element name="ADDR3" type="ofx:AddressType" minOccurs="0"/>
    #        </xsd:sequence>
    #      </xsd:sequence>
    #      <xsd:element name="CITY" type="ofx:AddressType"/>
    #      <xsd:element name="STATE" type="ofx:StateType"/>
    #      <xsd:element name="POSTALCODE" type="ofx:ZipType"/>
    #      <xsd:element name="COUNTRY" type="ofx:CountryType" minOccurs="0"/>
    #      <xsd:element name="PHONE" type="ofx:PhoneType"/>
    #    </xsd:sequence>
    #  </xsd:complexType>
    #
    def to_ofx
      buf = ""
      # Set margin=6 to indent it nicely within the output from Transaction.to_ofx
      x = Builder::XmlMarkup.new(:target => buf, :indent => 2, :margin=>6)
      x.PAYEE {
        x.NAME name
        x.ADDR1 address
        x.CITY city
        x.STATE state
        x.POSTALCODE postalcode
        x.COUNTRY country unless country.nil? # minOccurs="0" in schema (above)
        x.PHONE phone
      }
      return buf
    end
    
    ##
    # Produces the Payee as a row of comma separated values
    # (delegates to +to_csv+)
    #
    def to_s
      to_csv
    end

  end # class Payee
end # module

