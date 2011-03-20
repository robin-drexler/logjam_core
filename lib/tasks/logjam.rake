namespace :logjam do
  # avoid loading the rails env if it's not necessary
  def logjam_dir
    File.expand_path(File.dirname(__FILE__) + '/../../')
  end
  def app_dir
    File.expand_path(logjam_dir + '/../../../')
  end
  namespace :assets do
    desc "create symbolic links for logjam assets in the public directory"
    task :link do
      system("ln -nsf #{logjam_dir}/assets/stylesheets/logjam.css #{app_dir}/public/stylesheets/logjam.css")
      system("ln -nsf #{logjam_dir}/assets/stylesheets/jdpicker.css #{app_dir}/public/stylesheets/jdpicker.css")

      system("ln -nsf #{logjam_dir}/assets/images/scatter_plot.jpg #{app_dir}/public/images/scatter_plot.jpg")
      system("ln -nsf #{logjam_dir}/assets/images/zoom.png #{app_dir}/public/images/zoom.png")
      system("ln -nsf #{logjam_dir}/assets/images/zoom_in.png #{app_dir}/public/images/zoom_in.png")
      system("ln -nsf #{logjam_dir}/assets/images/zoom_out.png #{app_dir}/public/images/zoom_out.png")
      system("ln -nsf #{logjam_dir}/assets/images/stream.gif #{app_dir}/public/images/stream.gif")

      system("ln -nsf #{logjam_dir}/assets/images/bg_hover.png #{app_dir}/public/images/bg_hover.png")
      system("ln -nsf #{logjam_dir}/assets/images/bg_selectable.png #{app_dir}/public/images/bg_selectable.png")
      system("ln -nsf #{logjam_dir}/assets/images/bg_selected.png #{app_dir}/public/images/bg_selected.png")
      system("ln -nsf #{logjam_dir}/assets/images/table_sort_desc.png #{app_dir}/public/images/table_sort_desc.png")
      system("ln -nsf #{logjam_dir}/assets/images/table_sorted_desc.png #{app_dir}/public/images/table_sorted_desc.png")
      system("ln -nsf #{logjam_dir}/assets/images/checkmark.png #{app_dir}/public/images/checkmark.png")

      system("ln -nsf #{logjam_dir}/assets/images/unknown.png #{app_dir}/public/images/unknown.png")
      system("ln -nsf #{logjam_dir}/assets/images/fatal.png #{app_dir}/public/images/fatal.png")
      system("ln -nsf #{logjam_dir}/assets/images/error.png #{app_dir}/public/images/error.png")
      system("ln -nsf #{logjam_dir}/assets/images/warn.png #{app_dir}/public/images/warn.png")
      system("ln -nsf #{logjam_dir}/assets/images/info.png #{app_dir}/public/images/info.png")
      system("ln -nsf #{logjam_dir}/assets/images/debug.png #{app_dir}/public/images/debug.png")

      system("ln -nsf #{logjam_dir}/assets/javascripts/protovis-r3.2.js #{app_dir}/public/javascripts/protovis-r3.2.js")
      system("ln -nsf #{logjam_dir}/assets/javascripts/jquery-1.4.2.min.js #{app_dir}/public/javascripts/jquery-1.4.2.min.js")
      system("ln -nsf #{logjam_dir}/assets/javascripts/jquery.jdpicker.js #{app_dir}/public/javascripts/jquery.jdpicker.js")

      system("ln -nsf #{logjam_dir}/assets/javascripts/jquery-ui-1.8.5.custom.min.js #{app_dir}/public/javascripts/jquery-ui-1.8.5.custom.min.js")
      system("ln -nsf #{logjam_dir}/assets/stylesheets/smoothness #{app_dir}/public/stylesheets/smoothness")
    end
  end

  namespace :plots do
    desc "remove generated plots"
    task :clear do
      system("rm -f #{app_dir}/public/images/plot-*")
    end
  end

  namespace :db do
    desc "ensure indexes"
    task :reindex => :environment do
      Logjam.ensure_indexes
    end

    desc "remove old requests"
    task :clean => :environment do
      Logjam.remove_old_requests
    end

    desc "update severities"
    task :update_severities => :environment do
      Logjam.update_severities
    end
  end

  namespace :daemons do
    def service_dir
      ENV['LOGJAM_SERVICE_DIR'] || "#{app_dir}/service"
    end

    def template_dir
      File.expand_path(File.dirname(__FILE__) + "/../../services/")
    end

    def service_paths
      Dir["#{service_dir}/*"]
    end

    def services
      service_paths.join(' ')
    end

    def importer_specs
      YAML.load_file("#{ ENV['LOGJAM_DIR'] || app_dir }/config/logjam_amqp.yml")
    end

    def clean_path(paths)
      paths.map{|p| p.gsub(/\/+/,'/')}.uniq.join(':')
    end

    def install_service(template_name, service_name, substitutions={})
      target_dir = "#{service_dir}/#{service_name}"
      substitutions.merge!(:LOGJAM_DIR => ENV['LOGJAM_DIR'] || app_dir,
                           :RAILSENV => ENV['RAILS_ENV'] || "development",
                           :GEMHOME => Gem.dir,
                           :GEMPATH => clean_path(Gem.path)
                           :DAEMON_PATH => clean_path(ENV['PATH'].split(':')))
      system("mkdir -p #{target_dir}/log/logs")
      # order is important here: always create the dependent log service first!
      scripts = %w(log/run run)
      scripts.each do |script|
        template = File.read("#{template_dir}/#{template_name}/#{script}")
        substitutions.each do |k,v|
          template.gsub!(%r[#{k}], v)
        end
        File.open("#{target_dir}/#{script}", "w"){|f| f.puts template}
        system("chmod 755 #{target_dir}/#{script}")
      end
      service_name
    end

    desc "Install logjam daemons"
    task :install do
      system("mkdir -p #{service_dir}")
      installed_services = []
      importer_specs.each do |i, h|
        next if ENV['RAILS_ENV'] == 'production' && h['env'] == 'development'
        installed_services << install_service("importer", "importer-#{i}", :IMPORTER => i)
        if clusters = h["clusters"]
          clusters.each do |c|
            installed_services << install_service("parser", "parser-#{i}-#{c}", :IMPORTER => i, :CLUSTER => c.to_s)
          end
        else
          installed_services << install_service("parser", "parser-#{i}", :IMPORTER => i, :CLUSTER => '')
        end
      end
      installed_services << install_service("livestream", "live-stream")
      old_services = service_paths.map{|f| f.split("/").compact.last} - installed_services
      old_services.each do |old_service|
        puts "removing old service #{old_service}"
        system("rm -rf #{service_dir}/#{old_service}")
      end
    end

    desc "Start logjam daemons"
    task :start do
      system("sv up #{services}")
    end

    desc "Stop logjam daemons"
    task :stop do
      system("sv down #{services}")
    end

    desc "Show logjam daemons status"
    task :status do
      system("sv status #{services}")
    end

    desc "Restart logjam daemons"
    task :restart => [:stop, :start]

  end

end
