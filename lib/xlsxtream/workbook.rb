# encoding: utf-8
require "stringio"
require "xlsxtream/xml"
require "xlsxtream/shared_string_table"
require "xlsxtream/workbook"
require "xlsxtream/io/rubyzip"
require "xlsxtream/io/directory"
require "xlsxtream/io/stream"

module Xlsxtream
  class Workbook

    class << self

      def open(data = nil, options = {})
        workbook = new(data, options)
        if block_given?
          begin
            yield workbook
          ensure
            workbook.close
          end
        else
          workbook
        end
      end

    end

    def initialize(data = nil, options = {})
      @options = options
      io_wrapper = options[:io_wrapper] || IO::RubyZip
      @io = io_wrapper.new(data || StringIO.new)
      @sst = SharedStringTable.new
      @worksheets = Hash.new { |hash, name| hash[name] = hash.size + 1 }
    end

    def write_worksheet(name = nil, options = {})
      use_sst = options.fetch(:use_shared_strings, @options[:use_shared_strings])
      name ||= "Sheet#{@worksheets.size + 1}"
      sheet_id = @worksheets[name]
      @io.add_file "xl/worksheets/sheet#{sheet_id}.xml"
      worksheet = Worksheet.new(@io, use_sst ? @sst : nil)
      yield worksheet if block_given?
      worksheet.close
      nil
    end
    alias_method :add_worksheet, :write_worksheet

    def close
      write_workbook
      write_styles
      write_sst unless @sst.empty?
      write_workbook_rels
      write_root_rels
      write_content_types
      @io.close
      nil
    end

    private

    def write_root_rels
      @io.add_file "_rels/.rels"
      @io << XML.header
      @io << XML.strip(<<-XML)
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
      XML
    end

    def write_workbook
      rid = "rId0"
      @io.add_file "xl/workbook.xml"
      @io << XML.header
      @io << XML.strip(<<-XML)
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <workbookPr date1904="false"/>
          <sheets>
      XML
      @worksheets.each do |name, sheet_id|
        @io << %'<sheet name="#{XML.escape_attr name}" sheetId="#{sheet_id}" r:id="#{rid.next!}"/>'
      end
      @io << XML.strip(<<-XML)
          </sheets>
        </workbook>
      XML
    end

    def write_styles
      @io.add_file "xl/styles.xml"
      @io << XML.header
      @io << XML.strip(<<-XML)
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <numFmts count="2">
            <numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/>
            <numFmt numFmtId="165" formatCode="yyyy\\-mm\\-dd hh:mm:ss"/>
            <numFmt numFmtId="166" formatCode="hh:mm:ss"/>
          </numFmts>
          <fonts count="1">
            <font>
              <sz val="12"/>
              <name val="Calibri"/>
              <family val="2"/>
            </font>
          </fonts>
          <fills count="2">
            <fill>
              <patternFill patternType="none"/>
            </fill>
            <fill>
              <patternFill patternType="gray125"/>
            </fill>
          </fills>
          <borders count="1">
            <border/>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="3">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
            <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
            <xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
          <dxfs count="0"/>
          <tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>
        </styleSheet>
      XML
    end

    def write_sst
      @io.add_file "xl/sharedStrings.xml"
      @io << XML.header
      @io << %'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="#{@sst.references}" uniqueCount="#{@sst.size}">'
      @sst.each_key do |string|
        @io << "<si><t>#{XML.escape_value string}</t></si>"
      end
      @io << '</sst>'
    end

    def write_workbook_rels
      rid = "rId0"
      @io.add_file "xl/_rels/workbook.xml.rels"
      @io << XML.header
      @io << '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      @worksheets.each do |name, sheet_id|
        @io << %'<Relationship Id="#{rid.next!}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{sheet_id}.xml"/>'
      end
      @io << %'<Relationship Id="#{rid.next!}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      @io << %'<Relationship Id="#{rid.next!}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>' unless @sst.empty?
      @io << '</Relationships>'
    end

    def write_content_types
      @io.add_file "[Content_Types].xml"
      @io << XML.header
      @io << XML.strip(<<-XML)
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      XML
      @io << '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>' unless @sst.empty?
      @worksheets.each_value do |sheet_id|
        @io << %'<Override PartName="/xl/worksheets/sheet#{sheet_id}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      end
      @io << '</Types>'
    end
  end
end
