require './compiler'
require 'progressbar'
require 'thor'
require 'zip/zip'

class TermProgress
  def begin(member, count)
    @progress_bar = ProgressBar.create(
      total: count,
      format: "Adding data to #{member} table: %p%% <%B>",
      smoothing: 0.5
    )
  end

  def step()
    @progress_bar.increment
  end

  def finish()
    @progress_bar.finish()
  end
end

class Manage < Thor
  no_tasks {
    def determine_version(gtfs_zipfile)
      parts = gtfs_zipfile.split('_')
      parts.length > 2 ? parts[1].to_i : Time.new.strftime('%Y%m%d').to_i
    end
  }

  desc "compile DATABASE_NAME GTFS_ZIPFILE", "compule"
  method_options :version => ''

  def compile(database_name, gtfs_zipfile)
    ver = options[:version].length > 0 ? options[:version].to_i : determine_version(gtfs_zipfile)

    puts "= Removing old database (#{database_name}.sqlite3)"
    fn = "#{database_name}.sqlite3"
    File.delete(fn) if File.exist? fn

    cmp = Compiler.new(database_name, ver)
    progress = TermProgress.new

    members = ['calendar', 'calendar_dates', 'stops', 'routes', 'trips', 'stop_times']

    puts "= Compiling (versions => [schema: #{cmp.schema_version}; feed: #{ver}])"
    Zip::ZipFile.open(gtfs_zipfile) do |zf|
      members.each do |m|
        cmp.add(m, zf.read("#{m}.txt"), progress)
      end
    end

    puts "= Making indexes"
    cmp.make_indexes
  end
end
