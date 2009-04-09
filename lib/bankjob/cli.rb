require 'rubygems'
require 'ostruct'
require 'optparse'
require 'logger'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'bankjob_runner.rb'

module Bankjob
  class CLI

    NEEDED = "Needed" # constant to indicate compulsory options
    NOT_NEEDED = "Not Needed" # constant to indicate no-longer compulsory options

    def self.execute(stdout, argv)
      # The BanjobOptions module above, through the magic of OptiFlags
      # has augmented ARGV with the command line options accessible through
      # ARGV.flags.
      runner = BankjobRunner.new()
      runner.run(parse(argv), stdout)
    end # execute

    ##
    # Parses the command line arguments using OptionParser and returns
    # an open struct with an attribute for each option
    #
    def self.parse(args)
      options = OpenStruct.new

      # Set the default options
      options.scraper = NEEDED
      options.scraper_args = []
      options.log_level = Logger::WARN
      options.log_file = nil
      options.debug = false
      options.input = nil
      options.ofx = false # ofx is the default but only if csv is false
      options.ofx_out = false
      options.csv = false
      options.csv_out = nil # allow for separate csv and ofx output files
      options.wesabe_help = false
      options.wesabe_upload = false
      options.wesabe_args = nil
      options.logger = nil

      opt = OptionParser.new do |opt|
  
        opt.banner = "Bankjob - scrapes your online banking website and produces an OFX or CSV document.\n" +
                     "Usage: bankjob [options]\n"

        opt.version = Bankjob::BANKJOB_VERSION
  
        opt.on('-s', '--scraper SCRAPER',
               "The name of the ruby file that scrapes the website.\n") do |file|
          options.scraper = file
        end

        opt.on('--scraper-args ARGS',
               "Any arguments you want to pass on to your scraper.",
               "The entire set of arguments must be quoted and separated by spaces",
               "but you can use single quotes to specify multi-word arguments for",
               "your scraper.  E.g.",
               "   -scraper-args \"-user Joe -password Joe123 -arg3 'two words'\""," ",
               "This assumes your scraper accepts an array of args and knows what",
               "to do with them, it will vary from scraper to scraper.\n") do |sargs|
          options.scraper_args = sub_args_to_array(sargs)
        end

        opt.on('-i', '--input INPUT_HTML_FILE',
               "An html file used as the input instead of scraping the website -",
               "useful for debugging.\n") do |file|
          options.input = file
        end

        opt.on('-l', '--log LOG_FILE',
               "Specify a file to log information and debug messages.",
               "If --debug is used, log info will go to the console, but if neither",
               "this nor --debug is specfied, there will be no log.",
               "Note that the log is rolled over once per week\n") do |log_file|
          options.log_file = log_file
        end

        opt.on('q', '--quiet', "Suppress all messages, warnings and errors.",
               "Only fatal errors will go in the log") do
          options.log_level = Logger::FATAL
        end

        opt.on( '--verbose', "Log detailed informational messages.\n") do
          options.log_level = Logger::INFO
        end

        opt.on('--debug',
               "Log debug-level information to the log",
               "if here is one and put debug info in log\n") do
          options.log_level = Logger::DEBUG
          options.debug = true
        end

        opt.on('--ofx [FILE]',
               "Write out the statement as an OFX2 compliant XML document."," ",
               "If FILE is not specified, the XML is dumped to the console.",
               "If FILE specifies a directory then a new file will be created with a",
               "name generated from the dates of the first and last transactions.",
               "If FILE specifies a file that already exists it will be overwritten."," ",
               "(Note that ofx is the default format unless --csv is specified,",
               "and that both CSV and OFX documents can be produced by specifying",
               "both options.)\n") do |file|
          options.ofx = true
          options.ofx_out = file
        end

        opt.on('--csv [FILE]',
               "Writes out the statement as a CSV (comma separated values) document.",
               "All of the information available including numeric values for amount,",
               "raw and rule-generated descriptions, etc, are produced in the CSV document.", " ",
               "The document produced is suitable for loading into a spreadsheet like",
               "Microsoft Excel with the dates formatted to allow for auto recognition.",
               "This option can be used in conjunction with --ofx or --wesabe to produce",
               "a local permanent log of all the data scraped over time.", " ",
               "If FILE is not specified, the CSV is dumped to the console.",
               "If FILE specifies a directory then a new file will be created with a",
               "name generated from the dates of the first and last transactions.",
               "If FILE specifies a file that already exists then the new statement",
               "will be appended to the existing one in that file with care taken to",
               "merge removing duplicate entries.\n",
               "[WARNING - this merging does not yet function properly - its best to specify a directory for now.]\n"
             ) do |file|
          # TODO update this warning when we have merging working
          options.csv = true
          options.csv_out = file
        end

        opt.on('--wesabe-help [WESABE_ARGS]',
               "Show help information on how to use Bankjob to upload to Wesabe.",
               "Optionally use with \"wesabe-user password\" to get Wesabe account info.",
               "Note that the quotes around the WESABE_ARGS to send both username",
               "and password are necessary.", " ",
               "Use --wesabe-help with no args for more details.\n") do |wargs|
          options.wesabe_args = sub_args_to_array(wargs)
          options.wesabe_help = true
          options.scraper = NOT_NEEDED # scraper is not NEEDED when this option is set
        end

        opt.on('--wesabe WESABE_ARGS',
               "Produce an OFX document from the statement and upload it to a Wesabe account.",
               "WESABE_ARGS must be quoted and space-separated, specifying the wesabe account",
               "username, password and - if there is more than one - the wesabe account number.", " ",
               "Before trying this, use bankjob --wesabe-help to get more information.\n"
             ) do |wargs|
          options.wesabe_args = sub_args_to_array(wargs)
          options.wesabe_upload = true
        end

        opt.on('--version', "Display program version and exit.\n" ) do
          puts opt.version
          exit
        end
 
        opt.on_tail('-h', '--help', "Display this usage message and exit.\n" ) do
          puts opt
          puts <<-EOF

  Some common options:

    o Debugging:
      --debug --scraper bpi_scraper.rb --input /tmp/DownloadedPage.html --ofx
     
    o Regular use: (output ofx documents to a directory called 'bank')
      --scraper /bank/mybank_scraper.rb --scraper-args "me mypass123" --ofx /bank --log /bank/bankjob.log --verbose
      
    o Abbreviated options with CSV output: (output csv appended continuously to a file)
      -s /bank/otherbank_scraper.rb --csv /bank/statements.csv -l /bank/bankjob.log -q

    o Get help on using Wesabe:
      --wesabe-help

    o Upload to Wesabe: (I have 4 Wesabe accounts and am uploading to the 3rd)
      -s /bank/mybank_scraper.rb --wesabe "mywesabeuser password 3"  -l /bank/bankjob.log --debug
  EOF
          exit!
        end
  
      end #OptionParser.new

      begin
        opt.parse!(args)
        _validate_options(options) # will raise exceptions if options are invalid
        _init_logger(options) # sets the logger
      rescue Exception => e
        puts e, "", opt
        exit
      end
  
      return options
    end #self.parse

    private

    # Checks if the options are valid, raising exceptiosn if they are not.
    # If the --debug option is true, then messages are dumped but flow continues
    def self._validate_options(options)
      begin 
        #Note that OptionParser doesn't really handle compulsory arguments so we use
        #our own mechanism
        if options.scraper == NEEDED
          raise "Incomplete arguments: You must specify a scaper ruby script with --scraper"
        end

        # Add in the --ofx option if it is not already specified and if --csv is not specified either
        options.ofx = true unless options.csv or options.wesabe_upload
      rescue Exception => e
        if options.debug
          # just dump the message and eat the exception - 
          # we may be using dummy values for debugging
          puts "Ignoring error in options due to --debug flag: #{e}"
        else
          raise e
        end
      end #begin/rescue

    end #_validate_options

    ##
    # Initializes the logger taking the log-level and the log
    # file name from the command line +options+ and setting the logger back on
    # the options struct as +options.logger+
    #
    # Note that the level is not set explicitly in options but derived from
    # flag options like --verbose (INFO), --quiet (FATAL) and --debug (DEBUG)
    #
    def self._init_logger(options)
      # the log log should roll over weekly
      if options.log_file.nil?
        if options.debug 
          # if debug is on but no logfile is specified then log to console
          options.log_file = STDOUT
        else
          # Setting the log level to UNKNOWN effectively turns logging off
          options.log_level = Logger::UNKNOWN
        end
      end
      options.logger = Logger.new(options.log_file, 'weekly') # roll over weekly
      options.logger.level = options.log_level
    end
   
    # Takes a string of arguments and splits it into an array, allowing for 'single quotes'
    # to join words into a single argument.
    # (Note that parentheses are used to group to exclude the single quotes themselves, but grouping
    #  results in scan creating an array of arrays with some nil elements hence flatten and delete)
    def self.sub_args_to_array(subargs)
      return nil if subargs.nil?
      return subargs.scan(/([^\s']+)|'([^']*)'/).flatten.delete_if { |x| x.nil?}
    end

  end #class CLI
end
