# -*- encoding: utf-8 -*-

require 'hexapdf/error'
require 'hexapdf/pdf/serializer'
require 'hexapdf/pdf/xref_section'
require 'hexapdf/pdf/type/xref_stream'
require 'hexapdf/pdf/type/object_stream'

module HexaPDF
  module PDF

    # Writes the contents of a PDF document to an IO stream.
    class Writer

      # Creates a new writer object for the given HexaPDF document that gets written to the IO
      # object.
      def initialize(document, io)
        @document = document
        @io = io

        @io.binmode
        @io.seek(0, IO::SEEK_SET) #TODO: incremental update!

        @serializer = Serializer.new
      end

      # Writes the document to the IO object.
      def write
        write_file_header

        pos = nil
        @document.revisions.reverse_each do |rev|
          pos = write_revision(rev, pos)
        end
      end

      private

      # Writes the PDF file header.
      #
      # See: PDF1.7 s7.5.2
      def write_file_header
        #TODO: Need some method to calculate pdf version
        @io << "%PDF-1.7\n%\xCF\xEC\xFF\xE8\xD7\xCB\xCD\n"
      end

      # Writes the given revision.
      #
      # The +previous_xref_pos+ argument needs to contain the byte position of the previous
      # cross-reference section or stream if applicable.
      def write_revision(rev, previous_xref_pos = nil)
        xref_stream, object_streams = xref_and_object_streams(rev)
        object_streams.each {|stm| stm.write_objects(rev)}

        xref_section = XRefSection.new
        rev.each do |obj|
          if obj.null?
            xref_section.add_free_entry(obj.oid, obj.gen)
          elsif (objstm = object_streams.find {|stm| stm.object_index(obj)})
            xref_section.add_compressed_entry(obj.oid, objstm.oid, objstm.object_index(obj))
          elsif !obj.kind_of?(Type::XRefStream)
            xref_section.add_in_use_entry(obj.oid, obj.gen, @io.pos)
            write_indirect_object(obj)
          end
        end

        trailer = rev.trailer.value.dup
        if previous_xref_pos
          trailer[:Prev] = previous_xref_pos
        else
          trailer.delete(:Prev)
        end

        startxref = @io.pos
        if xref_stream
          xref_section.add_in_use_entry(xref_stream.oid, xref_stream.gen, startxref)
          xref_stream.update_with_xref_section_and_trailer(xref_section, trailer)
          write_indirect_object(xref_stream)
        else
          write_xref_section(xref_section)
          write_trailer(trailer)
        end

        write_startxref(startxref)

        startxref
      end

      # :call-seq:
      #    writer.xref_and_object_streams    -> [xref_stream, object_streams]
      #
      # Returns the cross-reference and object streams of the given revision.
      #
      # An error is raised if the revision contains object streams and no cross-reference stream, or
      # if it contains multiple cross-reference streams.
      def xref_and_object_streams(rev)
        xref_stream = nil
        object_streams = []

        rev.each do |obj|
          if obj.kind_of?(Type::ObjectStream)
            object_streams << obj
          elsif obj.kind_of?(Type::XRefStream)
            unless xref_stream.nil?
              raise HexaPDF::Error, "A revision can only have one xref stream, at least two detected"
            end
            xref_stream = obj
          end
        end

        if object_streams.size > 0 && xref_stream.nil?
          raise HexaPDF::Error, "Cannot use object streams when there is no xref stream"
        end

        [xref_stream, object_streams]
      end

      # Writes the single indirect object which may be a stream object or another object.
      def write_indirect_object(obj)
        @io << "#{obj.oid} #{obj.gen} obj\n"
        obj.kind_of?(Stream) ? write_stream_object(obj) : write_object(obj)
        @io << "\nendobj\n"
      end

      # Writes the stream object.
      #
      # See: PDF1.7 s7.3.8
      def write_stream_object(obj)
        data = Filter.string_from_source(obj.stream_encoder)
        obj.value[:Length] = data.size

        write_object(obj)

        @io << "stream\n"
        @io << data
        @io << "\nendstream"
      end

      # Writes the object.
      def write_object(obj)
        @io << @serializer.serialize(obj)
      end

      # Writes the cross-reference section.
      #
      # See: PDF1.7 s7.5.4
      def write_xref_section(xref_section)
        @io << "xref\n"
        xref_section.each_subsection do |entries|
          @io << "#{entries.empty? ? 0 : entries.first.oid} #{entries.size}\n"
          entries.each do |entry|
            if entry.in_use?
              @io << "%010d %05d n \n" % [entry.pos, entry.gen]
            elsif entry.free?
              @io << "0000000000 65535 f \n"
            else
              # Should never occur since we create the xref section!
              raise HexaPDF::Error, "Cannot use xref type #{entry.type} in cross-reference section"
            end
          end
        end
      end

      # Writes the trailer dictionary.
      #
      # See: PDF1.7 s7.5.5
      def write_trailer(trailer)
        @io << "trailer\n#{@serializer.serialize(trailer)}\n"
      end

      # Writes the startxref line needed for cross-reference sections and cross-reference streams.
      #
      # See: PDF1.7 s7.5.5, s7.5.8
      def write_startxref(startxref)
        @io << "startxref\n#{startxref}\n%%EOF\n"
      end

    end

  end
end
