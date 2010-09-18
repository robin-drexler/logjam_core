module Logjam

  # Methods added to this helper will be available to all templates in the application.
  module LogjamHelper
    def time_number(f)
      number_with_precision(f.to_f, :delimiter => ",", :separator => ".", :precision => 2)
    end

    def memory_number(f)
      number_with_precision(f.floor, :delimiter => ",", :separator => ".", :precision => 0)
    end

    def seconds_to_human(seconds)
      case
      when seconds < 60
        "#{number_with_precision(seconds, :precision => 2, :delimiter => ',')}s"
      when seconds < 3600
        "#{number_with_precision(seconds / 60, :precision => 2, :delimiter => ',')}m"
      else
        "#{number_with_precision(seconds / 3600, :precision => 2, :delimiter => ',')}h"
      end
    end

    def minute_to_human(minute_of_day)
      "%02d:%02d" % minute_of_day.divmod(60)
    end

    def distribution_kind(resource)
      case Resource.resource_type(resource)
      when :time
        :request_time_distribution
      when :memory
        case resource
        when 'allocated_objects'
          :allocated_objects_distribution
        else
          :allocated_size_distribution
        end
      else
        nil
      end
    end

    def clean_params(params)
      FilteredDataset.clean_url_params params
    end

    def sometimes_link_grouping_result(result, grouping, params)
      value = result.send(grouping)
      ppage = params[:page]
      if grouping.to_sym == :page && ppage !~ /Others/ && (ppage != @page || ppage =~ /^::/)
        params = params.merge(grouping => value)
        params[:page] = without_module(ppage) unless @page == "::"
        link_to(h(value), {:params => clean_params(params)}, :title => "filter with #{h(value)}")
      else
        "<span class='dead-link'>#{h(value)}</span>"
      end
    end

    def sometimes_link_number_of_requests(result, grouping, options)
      n = number_with_delimiter(result.count.to_i)
      if :page == grouping.to_sym && result.page != "Others..."
        link_to n, options, :title => "show requests"
      else
        n
      end
    end

    def sometimes_link_stddev(page, resource)
      stddev = page.stddev(resource)
      n = number_with_precision(stddev, :precision => 0 , :delimiter => ',')
      if stddev > 0 && page.page != "Others..."
        options = {:params => clean_params(params.merge(:page => without_module(page.page), :action => distribution_kind(resource)))}
        link_to(n, options, :title => distribution_kind(resource).to_s.gsub(/_/,''))
      else
        n
      end
    end

    def link_to_request(text, options, response_code)
      if response_code == 500
        link_to(text, options, :title => "show request", :class => "error")
      else
        link_to(text, options, :title => "show request")
      end
    end

    def sometimes_link_errors(page, n)
      if n == 0
        ""
      elsif page == "Others..."
        n
      else
        link_to(n, :params => params.slice(:year,:month,:day).merge(:action => "errors", :page => without_module(page)))
      end
    end

    def without_module(page)
      page.blank? ? page : page.sub(/^::(.)/){$1}
    end

    def html_attributes_for_grouping(grouping)
      if params[:grouping] == grouping
        "class='active'"
      else
        "class='inactive' onclick=\"view_grouping('#{grouping}')\""
      end
    end

    def html_attributes_for_resource_type(resource_type)
      resource = Resource.default_resource(resource_type)
      if Resource.resource_type(params[:resource]) == resource_type.to_sym
        "class='active' title='analyzing #{resource_type} resources' onclick=\"view_resource('#{resource}')\""
      else
        "class='inactive' title='analyze #{resource_type} resources' onclick=\"view_resource('#{resource}')\""
      end
    end

    def resource_descriptions
      resources = Resource.time_resources + Resource.memory_resources + Resource.call_resources
      groupings = Resource.groupings
      functions = Resource.grouping_functions.reject(&:blank?)
      g = {}
      groupings.each do |grouping|
        r = {}
        resources.each do |resource|
          if grouping.to_sym == :request || resource.to_sym == :requests
            r[resource] = Resource.description(resource, grouping, :sum)
          else
            f = {}
            functions.each do |function|
              f[function] = Resource.description(resource, grouping, function)
            end
            r[resource] = f
          end
          g[grouping] = r
        end
      end
      g.to_json
    end

    SEVERITY_LABELS = %w(DEBUG INFO WARN ERROR FATAL)

    def format_severity(severity)
      severity.is_a?(String) ? severity : (severity && SEVERITY_LABELS[severity]) || "UNKNOWN"
    end

    def severity_icon(severity)
      img = format_severity(severity).downcase
      image_tag("#{img}.png", :alt => "severity: #{img}", :title => "severity: #{img}")
    end

    def extract_lines(log_lines)
      log_lines.first.is_a?(Array) ? (log_lines.map{|s,l| l}) : log_lines
    end

    def extract_exception(log_lines)
      extract_lines(log_lines).map{|l| safe_h(l)}.detect{|l| l =~ /rb:\d+:in|Error|Exception/}.to_s[0..70]
    end

    def extract_error(log_lines)
      return extract_exception(log_lines) if log_lines.first.is_a?(String)
      safe_h(log_lines.detect{|(s,l)| s >= 3}[1])[0..70]
    end

    def format_log_level(l)
#      "&#10145;"
      severity_icon(l)
    end

    def format_log_line(line)
      if line.is_a?(String)
        level = 1
      else
        level, line = line
      end
      l = safe_h line
      level = 2 if level == 1 && (l =~ /rb:\d+:in|Error|Exception/) && (l !~ /^(Rendering|Completed|Processing|Parameters)/)
      colored_line = level > 1 ? "<span class='error'>#{l}</span>" : l
      "#{format_log_level(level)} #{colored_line}"
    end

    # try to fix broken string encodings. most of the time the string is latin-1 encoded
    if RUBY_VERSION >= "1.9"
      def safe_h(s)
        h(s)
      rescue ArgumentError
        raise unless $!.to_s == "invalid byte sequence in UTF-8"
        logger.debug "#{$!} during html escaping".upcase
        begin
          h(s.force_encoding('ISO-8859-1').encode('UTF-8', :undef => :replace))
        rescue ArgumentError
          h(s.force_encoding('ASCII-8BIT').encode('UTF-8', :undef => :replace))
        end
      end
    else
      def safe_h(s)
        h(s)
      end
    end
  end
end
