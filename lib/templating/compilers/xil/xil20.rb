# -*- coding: utf-8 -*-
module Templating::Compilers
  module Xil
    class Xil20

      class << self


        SCHEMA = Templating::Compilers::Xil::Schema::Definition.new(:xil20) do
          element(:template) do
            has_many :document
          end
          element(:document, nil, {}, {:title=>:string, :subject=>:string, :author=>:string, :keywords=>:string}) do
            has_many :pages
          end
          element(:page, nil, {}, {:format=>:page_format, :orientation=>:symbol, :margin=>:length4}) do
            has_many :parts, :tables, :iterations
          end
          element(:part, nil, {}, {:height=>:length}) do
            has_many :sets, :iterations
          end
          element(:table, nil, {:collection=>:variable}, {:variable=>:variable}) do
            has_many :columns
          end
          element(:list, nil, {:collection=>:variable}, {:variable=>:variable, :columns=>:integer, :size=>:length})
          element(:column, nil, {:label=>:string, :property=>:property, :width=>:length}, {:align=>:symbol, :format=>:symbol, :numeric=>:symbol, :separator=>:string, :delimiter=>:string, :unit=>:string, :precision=>:integer, :scale=>:integer})
          element(:set, nil, {}, {:left=>:length, :top=>:length}) do
            has_many :sets, :iterations, :texts, :cells, :rectangles, :lines, :images, :lists
          end
          element(:iteration, nil, {:collection=>:variable, :variable=>:variable})
          element(:text, nil, {:value=>:string}, {:left=>:length, :top=>:length, :align=>:symbol, :bold=>:boolean, :italic=>:boolean, :size=>:length, :color=>:color, :valign=>:symbol, :border=>:border, :font=>:string})
          # element(:cell, :string, {:left=>:length, :top=>:length, :align=>:symbol, :bold=>:boolean, :italic=>:boolean, :size=>:length, :color=>:color, :width=>:length, :font=>:string})
          element(:rectangle, nil, {:width=>:length, :height=>:length}, {:left=>:length, :top=>:length, :right=>:length, :border=>:border})
          element(:line, nil, {:path=>:path}, {:width=>:length, :border=>:border})
          element(:image, nil, {:value=>:string}, {:width=>:length, :height=>:length, :left=>:length, :top=>:length}) do
            has_many :sets, :iterations, :texts, :cells, :rectangles, :lines, :images, :lists
          end
        end


        # info = { :CreationDate => @now, :ModDate => @now }
        # info[:Producer] = escape(@producer) unless @producer.nil?
        # info[:Title]    = escape(@title) unless @title.nil?
        # info[:Subject]  = escape(@subject) unless @subject.nil?
        # info[:Author]   = escape(@author) unless @author.nil?
        # info[:Keywords] = escape(@keywords) unless @keywords.nil?
        # info[:Creator]  = escape(@creator) unless @creator.nil?   

        def compile(doc, options={})
          mode = options.delete(:mode) || :normal
          template = doc.root
          code = ""
          i = 0
          parameters = template.find('parameters/parameter')
          if parameters.size > 0
            unless mode == :debug
              code << "raise ArgumentError.new('Unvalid number of argument') if args.size != #{parameters.size}\n"
            end
            parameters.each do |p|
              code << "#{p.attributes['name']} = args[#{i}]\n"
              i+=1
            end
          end
          document = template.find('document')[0]
          info = parameters_hash(document, nil, mode)
          info = hash_to_code(info)
          info = ', '+info unless info.blank?
          code << "Templating::Writer.generate(:creator=>'Templating #{Templating.version}'#{info}#{', :debug=>true' if mode == :debug}) do |__|\n"
          code << compile_children(document, '__', mode).strip.gsub(/^/, '  ')+"\n"
          code << "end"
          # list = code.split("\n"); list.each_index{|x| puts((x+1).to_s.rjust(4)+": "+list[x])}
          # return "# encoding: utf-8\n"+'('+(mode==:debug ? code : code.gsub(/\s*\n\s*/, ';'))+')'
          return "# encoding: utf-8\n"+code
        end



        ATTRIBUTES = {
          :page=>[:format],
          :part=>[:height],
          :table=>[:collection],
          :list=>[:collection],
          :column=>[:label, :property, :width],
          :set=>[],
          :font=>[],
          :iteration=>[:variable, :collection],
          :text=>[:value],
          :cell=>[:value, :width],
          :rectangle=>[:width, :height],
          :line=>[:path],
          :image=>[:value, :width, :height]
        }
        
        CHILDREN = {
          :document=>[:page, :iteration],
          :page=>[:part, :table, :iteration],
          :part=>[:set, :iteration],
          :table=>[:column],
          :set=>[:set, :iteration, :font, :text, :cell, :rectangle, :line, :image, :list]
        }
        
        
        def hash_to_code(hash, wrapped = false)
          code = hash.collect do |k,v| 
            "#{k.inspect} => " + if v.is_a? Symbol
                                   v.inspect
                                 else
                                   v.to_s
                                 end
          end.join(', ')
          if wrapped
            return '{'+code+'}'
          else
            return code
          end
        end


        def str_to_measure(string, nvar)
          string = string.to_s
          m = if string.match(/\-?\d+(\.\d+)?mm/)
                string[0..-3]+'.mm'
              elsif string.match(/\-?\d+(\.\d+)?\%/)
                string[0..-2].to_f == 100 ? "#{nvar}.width" : (string[0..-2].to_f/100).to_s+"*#{nvar}.width"
              elsif string.match(/\-?\d+(\.\d+)?/)
                string
              else
                " (0) "
              end
          m = '('+m+')' if m.match(/^\-/)
          return m
        end

        def measure_to_float(string, max_width = 190.mm)
          string = string.to_s
          m = if string.match(/\-?\d+(\.\d+)?mm/)
                string[0..-3].to_d.mm
              elsif string.match(/\-?\d+(\.\d+)?\%/)
                puts "DEPRECATED: Percentage value will be removed from XIL"
                string[0..-2].to_d * max_width / 100
              elsif string.match(/\-?\d+(\.\d+)?/)
                string.to_d
              else
                0
              end
          return m.round(3)
        end

        def attrs_to_s(attrs, nvar, mode)
          attrs.collect{|k,v| ":#{k}=>#{attr_to_s(k, v, nvar, mode)}"}.join(', ')
        end
        
        def attr_to_s(attribute_name, attribute_value, variable_name, mode)
          case(attribute_name.to_sym)
          when :align, :valign, :numeric then
            ":#{attribute_value.strip.gsub(/\s+/,'_')}"
          when :top, :left, :right, :width, :height, :size, :border_width then
            str_to_measure(attribute_value, variable_name)
          when :margin, :padding then
            '['+attribute_value.strip.split(/\s+/).collect{|m| str_to_measure(m, variable_name)}.join(', ')+']'
          when :border then
            border = attribute_value.strip.split(/\s+/)
            raise Exception.new("Attribute border malformed: #{attribute_value.inspect}. Ex.: '1mm solid #123456'") if border.size!=3
            "{:width=>#{str_to_measure(border[0], variable_name)}, :style=>:#{border[1]}, :color=>#{border[2].inspect}}"
          when :collection then
            mode==:debug ? "[]" : attribute_value
          when :format
            if attribute_value.to_s.match(/x/)
              attribute_value.to_s.split(/x/)[0..1].collect{|x| str_to_measure(x.strip)}
            else
              "'#{attribute_value.to_s.upcase}'"
            end
          when :property then
            "'"+attribute_value.gsub(/\//, '.')+"'"
          when :resize, :fixed, :bold, :italic then
            attribute_value.lower == "true" ? "true" : "false"
          when :value, :label
            # attribute_value = "'"+attribute_value.gsub(/\'/, '\\\\\'')+"'"
            attribute_value = "'"+attribute_value.gsub(/\'/, '\\\\\'')+"'"
            attribute_value = attribute_value.gsub(/\{\{[^\}]+\}\}/) do |m|
              data = m[2..-3].to_s.gsub('\\\'', '\'').split('?')
              datum = data[0].gsub('/', '.')
              datum = case data[1].to_s.split('=')[0]
                      when 'format'
                        "::I18n.localize(#{datum}, :format=>:legal)"
                      when 'numeric'
                        "number_to_currency(#{datum}, :separator=>',', :delimiter=>' ', :unit=>'', :precision=>2)"
                      else
                        datum
                      end
              (mode==:debug ? "[VALUE]" : "'+#{datum}.to_s+'")
            end
            attribute_value = attribute_value[3..-1] if attribute_value.match(/^\'\'\+/)
            attribute_value = attribute_value[0..-4] if attribute_value.match(/\+\'\'$/)
            attribute_value
          when :path
            attribute_value.split(/\s*\;\s*/).collect{|point| '['+point.split(/\s*\,\s*/).collect{|m| str_to_measure(m, variable_name)}.join(', ')+']'}.join(', ')
          when :variable
            attribute_value.to_s.strip
          else
            "'"+attribute_value.gsub(/\'/, '\\\\\'')+"'"
          end
        end


        def pt_to_s(float)
          float.round(3).to_s.gsub(/^(\-?\d+\.\d{3})\d+$/, '\1')
        end

        def attr_to_code(string, type = :string)
          value = Templating::Compilers::Xil::Schema::Attribute.read(string, type)
          if type == :string
            "'"+value.gsub(/\'/, '\\\\\'')+"'"
          elsif type == :length
            pt_to_s(value)
          elsif type == :length4
            '['+value.collect{|x| pt_to_s(x)}.join(', ')+']'
          elsif [:page_format, :symbol].include?(type)
            value.inspect
          elsif type == :border
            "{:width=>#{pt_to_s(value[:width])}, :style=>#{value[:style].inspect}, :color=>#{value[:color].inspect}}"
          elsif type == :path
            '['+value.collect{|p| '['+pt_to_s(p[0])+', '+pt_to_s(p[1])+']'}.join(', ')+']'
          else
            value.to_s
          end
        end


        # def parameters(element, variable, mode)
        #   name = element.name.to_sym
        #   attributes, parameters = {}, []
        #   element.attributes.to_h.collect{|k,v| attributes[k.to_sym] = v}
        #   attributes[:value] ||= element.content.gsub(/\n/, '{{"\\n"}}') if name == :text
        #   (ATTRIBUTES[name]||[]).each{|attr| parameters << attr_to_s(attr, attributes.delete(attr), variable, mode)}
        #   attributes.delete(:if)
        #   attrs = attrs_to_s(attributes, variable, mode)
        #   attrs = ', '+attrs if !attrs.blank? and parameters.size>0
        #   return parameters.join(', ')+attrs, parameters, attributes
        # end

        # def parameters(element, variable, mode)
        #   name = element.name.to_sym
        #   attributes, parameters, hash = {}, [], {}
        #   element.attributes.to_h.collect{|k,v| attributes[k.to_sym] = v}
        #   attributes[:value] ||= element.content.gsub(/\n/, '{{"\\n"}}') if name == :text
        #   for name, value in attributes
        #     hash[attr] = attr_to_s(name, value, variable, mode)
        #   end
        #   for attr in ATTRIBUTES[name]||[]
        #     parameters << hash[attr]
        #   end
        #   # attributes.delete(:if)
        #   attrs = attrs_to_s(attributes, variable, mode)
        #   attrs = ', '+attrs if !attrs.blank? and parameters.size>0
        #   return parameters.join(', ')+attrs, hash, attributes
        # end


        def parameters_hash(element, variable, mode)
          name = element.name.to_sym
          attributes_hash = element.attributes.to_h
          hash = {}
          for attribute in SCHEMA[element.name].attributes
            if string = attributes_hash[attribute.name]
              # hash[attribute.name.to_sym] = attr_to_s(attribute.name, string, variable, mode)
              hash[attribute.name.to_sym] = attr_to_code(string, attribute.type)
            elsif attribute.required?
              raise Exception.new("Attribute '#{attribute.name}' is required for element '#{name}'")
            end
          end
          if SCHEMA[element.name].has_content?
            # hash[:content] =  attr_to_s(:content, element.content, variable, mode)
            hash[:content] =  attr_to_code(element.content, SCHEMA[element.name].content)
          end
          # hash.delete(:if)
          return hash
        end

        # Retrives true values
        def parameters_values(element)
          attributes_hash = element.attributes.to_h
          hash = {}
          for attribute in SCHEMA[element.name].attributes
            if string = attributes_hash[attribute.name]
              hash[attribute.name.to_sym] = attribute.read(string)
            elsif attribute.required?
              raise Exception.new("Attribute '#{attribute.name}' is required for element '#{name}'")
            end
          end
          if SCHEMA[element.name].has_content?
            hash[:content] =  element.read(string)
          end
          return hash
        end


        # Call code generation function for each children
        def compile_children(element, variable, mode, depth=0)
          code = ''
          children = SCHEMA[element.name].children
          element.each_element do |child|
            if children.include?(child.name)
              code << compile_element(child, variable, mode, depth).strip + "\n"
            end
          end
          return code 
        end

        def execute_children(element, variable_name, mode, depth=0)
          children = compile_children(element, variable_name, mode, depth)
          if children.blank?
            return ""
          else
            return " do |#{variable_name}|\n"+children.strip.gsub(/^/, '  ')+"\nend\n"
          end
        end

        # Generate code for given element
        def compile_element(element, variable, mode, depth=0)
          code  = ''
          name = element.name.to_sym
          children_variable = "_#{depth}"
          phash = parameters_hash(element, variable, mode)
          if name == :image
            file = phash.delete(:value)
            code << "if File.exist?((#{file}).to_s)\n"
            code << "  #{variable}.image(#{file}, #{hash_to_code(phash, true)})\n"
            code << "else\n"
            code << compile_children(element, variable, mode, depth).strip.gsub(/^/, '  ')+"\n"
            code << "end"

          elsif name == :iteration
            code << "for #{phash[:variable]} in #{phash[:collection]}\n" unless mode == :debug
            code << compile_children(element, variable, mode, depth).strip.gsub(/^/, '  ')+"\n"
            code << "end" unless mode == :debug

          elsif name == :line
            points = phash.delete(:path)
            code << "#{variable}.line(#{points[1..-2]}, #{hash_to_code(phash, true)})"

          elsif name == :list
            lines = phash.delete(:collection)
            code << "#{variable}.list(#{lines}, #{hash_to_code(phash, true)})"

          elsif name == :page
            code << "#{variable}.page(:size=>#{phash[:format]}, :orientation=>#{phash[:orientation]}, :margins=>#{phash[:margin]})"
            code << execute_children(element, children_variable, mode, depth+1)

          elsif name == :part
            code << "#{variable}.slice"
            code << "(:height => #{phash[:height]})" if phash[:height]
            code << execute_children(element, children_variable, mode, depth+1)

          elsif name == :rectangle
            if phash[:right]
              phash[:left] = "(#{variable}.width - #{phash.delete(:right)})"
            end
            code << "#{variable}.rectangle(#{hash_to_code(phash)})"

          elsif name == :set
            if phash.empty?
              code << compile_children(element, variable, mode, depth)
            else
              if phash[:right]
                phash[:left] = "(#{variable}.width - #{phash.delete(:right)})"
              end
              code << "#{variable}.box(#{hash_to_code(phash)}) do\n"
              code << compile_children(element, variable, mode, depth+1).strip.gsub(/^/, '  ')+"\n"
              code << "end\n"
            end

          elsif name == :table
            collection = phash.delete(:collection)
            # stroke = phash.delete(:border)
            record = phash[:variable] || '_r'
            columns = []
            start =  measure_to_float(element.attributes['left'])
            offset = start
            element.each_element do |e|
              if e.name == 'column'
                col = {:phash => parameters_hash(e, variable, mode), :attributes=>e.attributes}
                col[:offset] = offset
                col[:width] = measure_to_float(e.attributes['width'])
                offset += col[:width]
                columns << col
              end
            end
            code << "#{variable}.slice(:height => #{pt_to_s(1.mm)})\n"
            
            # Header
            code << "#{variable}.slice do |#{children_variable}|\n"
            code << "  row_height = 0\n"
            for column in columns
              code << "  _h = #{children_variable}.height_of(#{column[:phash][:label]}, :width=>#{pt_to_s(column[:width])})\n"
              code << "  row_height = _h if _h > row_height\n"
            end
            for column in columns
              code << "  #{children_variable}.text(#{column[:phash][:label]}, :left=>#{pt_to_s(column[:offset])}, :width=>#{pt_to_s(column[:width])}, :height=>row_height, :valign=>:center)\n"
              code << "  #{children_variable}.line([#{pt_to_s(column[:offset])}, 0], [#{pt_to_s(column[:offset])}, row_height])\n"
              # code << "  row_height = _b.height if _b.height > row_height\n"
            end
            code << "  #{children_variable}.line([#{pt_to_s(start)}, 0], [#{pt_to_s(offset)}, 0], [#{pt_to_s(offset)}, row_height], [#{pt_to_s(start)}, row_height])\n"
            code << "end\n"
            # Rows
            code << "for #{record} in #{collection}\n"
            code << "  #{variable}.slice do |#{children_variable}|\n"
            code << "    row_height = 0\n"
            for column in columns
              value = "#{record}."+column[:attributes][:property].gsub(/\//, '.')
              if column[:attributes]['format']
                value = "::I18n.localize(#{value}, :format=>#{column[:phash][:format]})"
                column[:phash][:align] ||= ":center"
              elsif column[:attributes]['numeric']
                curr_hash = column[:phash].select{|k,v| [:separator, :delimiter, :unit, :precision, :scale].include?(k)}
                value = "number_to_currency(#{value}, #{hash_to_code(curr_hash, true)})"
                column[:phash][:align] ||= ":right"
              end
              code << "    _b = #{children_variable}.text(#{value}.to_s, :left=>#{pt_to_s(column[:offset])}, :width=>#{pt_to_s(column[:width])})\n"
              code << "    row_height = _b.height if _b.height > row_height\n"
            end
            for column in columns
              code << "    #{children_variable}.line([#{pt_to_s(column[:offset])}, 0], [#{pt_to_s(column[:offset])}, row_height])\n"
            end
            code << "    puts 'ROW HEIGHT' + row_height.to_s\n"
            code << "    #{children_variable}.line([#{pt_to_s(start)}, 0], [#{pt_to_s(offset)}, 0], [#{pt_to_s(offset)}, row_height], [#{pt_to_s(start)}, row_height])\n"
            code << "  end\n"
            code << "end\n"

          elsif name == :text
            options = parameters_values(element)
            if right = options.delete(:right)
              if options[:width]
                options[:left] = '(width - #{pt_to_s(right+options[:width])})'
              else
                options[:left] = '0'
              end
            else
              options[:left] = pt_to_s(options[:left] || 0)
            end
            if options[:align] == :right and options[:width]
              options[:left] = "(#{options[:left]} - #{pt_to_s(options[:width])})"
            elsif options[:align] == :center and options[:width]
              options[:left] = "(#{options[:left]} - #{pt_to_s(options[:width]/2)})"
            elsif options[:align] != :left
              options[:left] = '0'
            end
            phash[:left] = options[:left]
            phash.delete(:right)
            value = phash.delete(:value)
            code << "#{variable}.text(#{value}, #{hash_to_code(phash, true)})"

          else
            raise Exception.new("Unknown element '#{name}'")
          end


          # Wrapper: font
          if element.attributes['font']
            code = "#{variable}.font('#{element.attributes['font']}') do\n#{code.strip.gsub(/^/,'  ')}\nend"
          end

          # Wrapper: if <condition>
          if element.attributes['if'] and mode != :debug
            code = "if #{element.attributes['if'].to_s.gsub(/\//,'.')}\n#{code.strip.gsub(/^/,'  ')}\nend"
          end
          return code.strip
        end



      end
    end
  end
end
