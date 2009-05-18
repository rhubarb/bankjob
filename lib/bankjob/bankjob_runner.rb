require 'rubygems'
require 'logger'
require 'bankjob.rb'

module Bankjob
  class BankjobRunner

    # Runs the bankjob application, loading and running the
    # scraper specified in the command line args and generating
    # the output file.
    def run(options, stdout)
      logger = options.logger

      if options.wesabe_help
        Bankjob.wesabe_help(options.wesabe_args, logger)
        exit(0) # Wesabe help describes to the user how to use the wesabe options then quits
      end

      # Load the scraper object dynamically, then scrape the web
      # to get a new bank statement
      scraper = Scraper.load_scraper(options.scraper, options, logger)

      begin
        statement = scraper.scrape_statement(options.scraper_args)
        statement = Scraper.post_process_transactions(statement)
      rescue Exception => e
        logger.fatal(e)
        puts "Failed to scrape a statement successfully with #{options.scraper} due to: #{e.message}\n"
        puts "Use --debug --log bankjob.log then check the log for more details"
        exit (1)
      end

      # a lot of if's here but we allow for the user to generate ofx
      # and csv to files while simultaneously uploading to wesabe

      if options.csv
        if options.csv_out.nil?
          puts write_csv_doc([statement], true) # dump to console with header, no file specified
        else
          csv_file = file_name_from_option(options.csv_out, statement, "csv")

          # Output data as comma separated values possibly merging
          if File.file?(csv_file)
            # TODO until we fix merging csv files are appended
            open(csv_file, "a") do |f|
              f.puts(write_csv_doc([statement]))
            end
            logger.info("Statement is being appended as csv to #{csv_file}")
            #
            # TODO fix the merging then uncomment this
#            old_file_path = csv_file
#            # The file already exists, lets load it and merge with the new data
#            old_statement = scraper.create_statement()
#            old_statement.from_csv(old_file_path, scraper.decimal)
#            begin
#              old_statement.merge!(statement)
#              statement = old_statement
#            rescue Exception => e
#              # the merge failed, so leave the statement as the original and store it separately
#              output_file = output_file + "_#{date_range}_merge_failed"
#              logger.warn("Merge failed, storing new data in #{output_file} instead of appending it to #{old_file_path}")
#              logger.debug("Merge failed due to: #{e.message}")
#            end
          else
            open(csv_file, "w") do |f|
              f.puts(write_csv_doc([statement], true)) # true = write with header
            end
            logger.info("Statement is being written as csv to #{csv_file}")
          end
        end
      end # if csv

      # Create an ofx document and write it if necessary
      if (options.ofx or options.wesabe_upload)
        ofx_doc = write_ofx_doc([statement])
      end

      # Output ofx file
      if options.ofx
        if options.ofx_out.nil?
          puts ofx_doc # dump to console, no file specified
        else
          ofx_file = file_name_from_option(options.ofx_out, statement, "ofx")
          open(ofx_file, "w") do |f|
            f.puts(ofx_doc)
          end
          logger.info("Statement is being output as ofx to #{ofx_file}")
        end
      end

      # Upload to wesabe if requested
      if options.wesabe_upload
        begin
          Bankjob.wesabe_upload(options.wesabe_args, ofx_doc, logger)
        rescue Exception => e
          logger.fatal("Failed to upload to Wesabe")
          logger.fatal(e)
          puts "Failed to upload to Wesabe: #{e.message}\n"
          puts "Try bankjob --wesabe-help for help on this feature."
          exit(1)
        end
      end
    end # run

    ##
    # Generates an OFX document to a string that starts with the stanadard
    # OFX header and contains the XML for the specified +statements+
    #
    def write_ofx_doc(statements)
      ofx = generate_ofx2_header
      statements.each do |statement|
        ofx << statement.to_ofx
      end
      return ofx
    end
 
    ##
    # Generates a CSV document to a string containing the transactions in
    # all of the specified +statements+
    #
    def write_csv_doc(statements, header = false)
      csv = ""
      csv << Statement.csv_header if header
      statements.each do |statement|
        csv << statement.to_csv
      end
      return csv
    end

    ##
    # Generates the (XML) OFX2 header lines that allow the OFX 2.0 document
    # to be recognized.
    #
    # <em>(Note that this is crucial for www.wesabe.com to accept the OFX
    # document in an upload)</em>
    #
    def generate_ofx2_header
      return <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<?OFX OFXHEADER="200" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE" VERSION="200"?>
      EOF
    end

    ##
    # Generates the (non-XML) OFX header lines that allow the OFX 1.0 document
    # to be recognized.
    #
    # <em>(Note that this is crucial for www.wesabe.com to accept the OFX
    # document in an upload)</em>
    #
    def generate_ofx_header
      return <<-EOF
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:1252
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE
      EOF
    end

    ##
    # Takes a name or path for an output file and a Statement and if the file
    # path is a directory, creates a new file name based on the date range
    # of the statement and returns a path to that file.
    # If +output_file+ is not a directory it is returned as-is.
    #
    def file_name_from_option(output_file, statement, type)
      # if the output_file is a directory, we create a new file name 
      if (output_file and File.directory?(output_file))
        # Create a date range string for the first and last transactions in the statement
        # This will looks something like: 20090130000000-20090214000000
        date_range = "#{Bankjob.date_time_to_ofx(statement.from_date)[0..7]}-#{Bankjob.date_time_to_ofx(statement.to_date)[0..7]}"
        filename = "#{date_range}.#{type}"
        output_file = File.join(output_file, filename)
      end
      # else we assume output_file is a file name/path already
      return output_file
    end
  end # class BankjobRunner
end # module Bankjob
