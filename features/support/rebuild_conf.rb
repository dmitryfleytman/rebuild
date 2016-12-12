class RebuildConfFile
  def initialize
    require 'ptools'
    require 'pathname'

    @path_name = File.join( Dir.home, '.rbld', 'rebuild.conf' )
  end

  attr_reader :path_name

  def fill(content)
    open(@path_name, 'w') { |f| f.write(content) }
  end

  def set_registry(url)
    fill %Q{
        REMOTE_NAME=origin
        REMOTE_origin="#{url}"
      }
  end
end
