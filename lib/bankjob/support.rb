
require 'rubygems'
require 'bankjob'

module Bankjob

  ##
  # Takes a date-time as a string or as a Time or DateTime object and returns
  # it as either a Time or a DateTime object.
  #
  # This is useful in the setter method of a date attribute allowing the date
  # to be set as any type but stored internally as an object compatible with
  # conversion through +strftime()+
  # (Bankjob::Transaction uses this internally in the setter for +date+ for example
  #
  def self.create_date_time(date_time_raw)
    if (date_time_raw.respond_to?(:rfc822)) then
      # It's already a Time or DateTime
      return date_time_raw
    elsif (date_time_raw.to_s.strip.empty?)
      # Nil or non dates are returned as nil
      return nil
    else
      # Assume it can be converted to a time
      return Time.parse(date_time_raw.to_s)
    end
  end

  ##
  # Takes a Time or DateTime and formats it in the correct format for OFX date elements.
  #
  # The OFX format is a string of digits in the format "YYMMDDHHMMSS".
  # For example, the 1st of February 2009 at 2:34PM and 56 second becomes "20090201143456"
  #
  # Note must use a Time, or DateTime, not a String, nor a Date.
  #
  def self.date_time_to_ofx(time)
    time.nil? ? "" : "#{time.strftime( '%Y%m%d%H%M%S' )}"
  end

  ##
  # Takes a Time or DateTime and formats in a suitable format for comma separated values files.
  # The format produced is suitable for loading into an Excel-like spreadsheet program
  # being automatically treated as a date.
  #
  # A string is returned with the format "YY-MM-DD HH:MM:SS".
  # For example, the 1st of February 2009 at 2:34PM and 56 second becomes "2009-02-01 14:34:56"
  #
  # Note must use a Time, or DateTime, not a String, nor a Date.
  #
  def self.date_time_to_csv(time)
    time.nil? ? "" : "#{time.strftime( '%Y-%m-%d %H:%M:%S' )}"
  end

  ##
  # Takes a string and capitalizes the first letter of every word
  # and forces the rest of the word to be lowercase.
  #
  # This is a utility method for use in scrapers to make descriptions
  # more readable.
  #
  def self.capitalize_words(message)
    message.downcase.gsub(/\b\w/){$&.upcase}
  end

  ##
  # converts a numeric +string+ to a float given the specified +decimal+
  # separator.
  #
  def self.string_to_float(string, decimal)
    return nil if string.nil?
    amt = string.gsub(/\s/, '')
    if (decimal == ',') # E.g.  "1.000.030,99"
      amt.gsub!(/\./, '')  # strip out . 1000s separator
      amt.gsub!(/,/, '.')  # replace decimal , with .
    elsif (decimal == '.')
      amt.gsub!(/,/, '')  # strip out comma 1000s separator
    end
    return amt.to_f
  end

  ##
  # Finds a selector field in a named +form+ in the given Mechanize +page+, selects
  # the suggested +label+
  def select_and_submit(page, form_name, select_name, selection)
    option = nil
    form  = page.form(form_name)
    unless form.nil?
      selector = form.field(select_name)
      unless selector.nil?
        option = select_option(selector, selection)
        form.submit
      end
    end
    return option
  end

  ##
  # Given a Mechanize::Form:SelectList +selector+ will attempt to select the option
  # specified by +selection+.
  # This algorithm is used:
  #   The first option with a label equal to the +selection+ is selected.
  #    - if none is found then -
  #   The first option with a value equal to the +selection+ is selected.
  #    - if none is found then -
  #   The first option with a label or value that equal to the +selection+ is selected
  #   after removing non-alphanumeric characters from the label or value
  #    - if none is found then -
  #   The first option with a lable or value that _contains_ the +selection+
  #
  # If matching option is found, the #select is called on it.
  # If no option is found, nil is returned - otherwise the option is returned
  #
  def select_option(selector, selection)
    options = selector.options.select { |o| o.text == selection }
    options = selector.options.select { |o| o.value == selection } if options.empty?
    options = selector.options.select { |o| o.text.gsub(/[^a-zA-Z0-9]/,"") == selection } if options.empty?
    options = selector.options.select { |o| o.value.gsub(/[^a-zA-Z0-9]/,"") == selection } if options.empty?
    options = selector.options.select { |o| o.text.include?(selection) } if options.empty?
    options = selector.options.select { |o| o.value.include?(selection) } if options.empty?

    option = options.first
    option.select() unless option.nil?
    return option
  end

  ##
  # Uploads the given OFX document to the Wesabe account specified in the +wesabe_args+
  #
  def self.wesabe_upload(wesabe_args, ofx_doc, logger)
    if (wesabe_args.nil? or (wesabe_args.length < 2 and wesabe_args.length > 3))
      raise "Incorrect number of args for Wesabe (#{wesabe_args}), should be 2 or 3."
    else
      load_wesabe
      wuser, wpass, windex = *wesabe_args
      wesabe = Wesabe.new(wuser, wpass)
      num_accounts = wesabe.accounts.length
      if num_accounts == 0
        raise "The user \"#{wuser}\" has no Wesabe accounts. Create one at www.wesabe.com before attempting to upload a statement."
      elsif (not windex.nil? and (num_accounts < windex.to_i))
        raise "The user \"#{wuser}\" has only #{num_accounts} Wesabe accounts, but the account index #{windex} was specified."
      elsif windex.nil?
        if num_accounts > 1
          raise "The user \"#{wuser}\" has #{num_accounts} Wesabe accounts, so the account index must be specified in the WESABE_ARGS."
        else
          # we have only one account, no need to specify the index
          windex = 1
        end
      elsif windex.to_i == 0
        raise "The Wesabe account index must be between 1 and #{num_accounts}. #{windex} is not acceptable"
      end
      logger.debug("Attempting to upload statement to the ##{windex} Wesabe account for user #{wuser}...")
      # Get the account at the index (which is not necessarily the index in the array 
      # so we use the account(index) method to get it
      account = wesabe.account(windex.to_i)
      uploader = account.new_upload
      uploader.statement = ofx_doc
      uploader.upload!
      logger.info("Uploaded statement to Wesabe account #{account.name}, the ##{windex} account for user #{wuser}, with the result: #{uploader.status}")
    end
  end

  ##
  # Helps the user determine how to upload to their Wesabe account.
  # 
  # When used with no args, will give generic help information.
  # When used with Wesabe account and password, will log into Wesabe and list
  # the users accounts, and suggest command line args to upload to each account.
  #
  def self.wesabe_help(wesabe_args, logger)
    if (wesabe_args.nil? or wesabe_args.length != 2)
      puts <<-EOF
Wesabe (http://www.wesabe.com) is an online bank account management tool (like Mint)
that allows you to upload (in some cases automatically) your bank statements and
automatically convert them into a more readable format to allow you to track
your spending and much more. Wesabe comes with its own community attached.

Bankjob has no affiliation with Wesabe, but allows you to upload the statements it
generates to your Wesabe account automatically.

To use Wesabe you need the Wesabe Ruby gem installed:
See the gem at http://github.com/wesabe/wesabe-rubygem
Install the gem with:
  $ sudo gem install -r --source http://gems.github.com/ wesabe-wesabe
(on Windows, omit the "sudo")

You also need your Wesabe login name and password, and, if you have
more than one account on Wesabe, the id number of the account.
This is not a real account number - it's simply a counter that Wesabe uses.
If you have a single account it will be '1', if you have two accounts the
second account will be '2', etc.

Bankjob will help you find this number by listing your Wesabe accounts for you.
Simply use:
  bankjob -wesabe_help "username password"
(The quotes are important - this is a single argument to Bankjob with two words)

If you already know the number of the account and you want to start uploading use:

  bankjob [other bankjob args] --wesabe "username password id"

E.g.
  bankjob --scraper bpi_scraper.rb --wesabe "bloggsy pw123 2"

If you only have a single account, you don't need to specify the id number
(but Bankjob will check and will fail with an error if you have more than one account)

  bankjob [other bankjob args] --wesabe "username password"

If in any doubt --wesabe-help "username password" will set you straight.

Troubleshooting:
- If you see an error like Wesabe::Request::Unauthorized, then chances
  are your username or password for Wesabe is incorrect.

- If you see an error "end of file reached" then it may be that you are logged
  into the Wesabe account to which you are trying to upload - perhaps in a browser.
  In this case, log out from Wesabe in the browser, _wait a minute_, then try again.
  EOF
    else
      load_wesabe
      begin
        puts "Connecting to Wesabe...\n"
        wuser, wpass = *wesabe_args
        wesabe = Wesabe.new(wuser, wpass)
        puts "You have #{wesabe.accounts.length} Wesabe accounts:"
        wesabe.accounts.each do |account|
          puts " Account Name: #{account.name}"
          puts "    wesabe id: #{account.id}"
          puts "   account no: #{account.number}"
          puts "         type: #{account.type}"
          puts "      balance: #{account.balance}"
          puts "         bank: #{account.financial_institution.name}"
          puts "To upload to this account use:"
          puts "  bankjob [other bankjob args] --wesabe \"#{wuser} password #{account.id}\""
          puts ""
          if wesabe.accounts.length == 1
            puts "Since you have one account you do not need to specify the id number, use:"
            puts "  bankjob [other bankjob args] --wesabe \"#{wuser} password\""
          end
        end
      rescue Exception => e
        msg =<<-EOF
Failed to get Wesabe account information due to: #{e.message}.
Check your username and password or use:
  bankjob --wesabe-help
with no arguments for more details.
        EOF
	logger.debug(msg)
	logger.debug(e)
	raise msg
      end
    end
  end # wesabe_help

  private

  def self.load_wesabe(logger = nil)
    begin
      require 'wesabe'
    rescue LoadError => error
      msg = <<-EOF
Failed to load the Wesabe gem due to #{error.module}
See the gem at http://github.com/wesabe/wesabe-rubygem
Install the gem with:
  $ sudo gem install -r --source http://gems.github.com/ wesabe-wesabe
EOF
      logger.fatal(msg) unless logger.nil?
      raise msg
    end
  end
end # module Bankjob


