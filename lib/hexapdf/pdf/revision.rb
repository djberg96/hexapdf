# -*- encoding: utf-8 -*-

require 'hexapdf/error'
require 'hexapdf/pdf/reference'
require 'hexapdf/pdf/utils/object_hash'

module HexaPDF
  module PDF

    # Embodies one revision of a PDF file, either the initial version or an incremental update.
    #
    # The purpose of a Revision object is to manage the objects and the trailer of one revision.
    # These objects can either be added manually or loaded from a cross-reference section or stream.
    # Since a PDF file can be incrementally updated, it can have multiple revisions.
    #
    # If a revision doesn't have an associated cross-reference section, then it wasn't created from
    # a file.
    #
    # See: PDF1.7 s7.5.6, Revisions
    class Revision

      include Enumerable

      # The trailer dictionary
      attr_reader :trailer

      # Creates a new Revision object.
      #
      # The trailer object needs to be supplied. If an +xref_section+ is supplied, then +parser+
      # also needs to be supplied!
      def initialize(trailer, xref_section: nil, parser: nil)
        @trailer = trailer
        @parser = parser
        @xref_section = xref_section || XRefSection.new
        @objects = Utils::ObjectHash.new
      end

      # :call-seq:
      #   revision.object(ref)    -> obj or nil
      #   revision.object(oid)    -> obj or nil
      #
      # Returns the object for the given reference or object number if such an object is available in
      # this revision, or +nil+ otherwise.
      #
      # If the revision has an entry but one that is pointing to a free entry in the cross-reference
      # section, an object representing PDF null is returned.
      def object(ref)
        oid, gen = if ref.kind_of?(ReferenceBehavior)
                     [ref.oid, ref.gen]
                   else
                     [ref, @objects.gen_for_oid(ref) || @xref_section.gen_for_oid(ref)]
                   end

        if @objects.entry?(oid, gen)
          @objects[oid, gen]
        elsif (xref_entry = @xref_section[oid, gen])
          add_without_check(@parser.load_object(xref_entry))
        else
          nil
        end
      end

      # :call-seq:
      #   revision.object?(ref)    -> true or false
      #   revision.object?(oid)    -> true or false
      #
      # Returns +true+ if the revision contains an object
      #
      # * for the exact reference if the parameter is a ReferenceBehaviour object, or else
      # * for the given object number.
      def object?(ref)
        if ref.kind_of?(ReferenceBehavior)
          @objects.entry?(ref.oid, ref.gen) || @xref_section.entry?(ref.oid, ref.gen)
        else
          @objects.entry?(ref) || @xref_section.entry?(ref)
        end
      end

      # :call-seq:
      #   revision.add(obj)   -> obj
      #
      # Adds the given object (needs to be a HexaPDF::PDF::Object) to this revision and returns it.
      def add(obj)
        if object?(obj.oid)
          raise HexaPDF::Error, "A revision can only contain one object with a given object number"
        elsif obj.oid == 0
          raise HexaPDF::Error, "A revision can only contain objects with non-zero object numbers"
        end
        add_without_check(obj)
      end

      # :call-seq:
      #   revision.delete(ref)
      #   revision.delete(oid)
      #
      # Deletes the object specified either by reference or by object number from this revision by
      # marking it as free.
      #
      # If the option +mark_as_free+ is set to +false+, the object is really deleted.
      def delete(ref_or_oid, mark_as_free: true)
        return unless object?(ref_or_oid)
        ref_or_oid = ref_or_oid.oid if ref_or_oid.kind_of?(ReferenceBehavior)

        if mark_as_free
          obj = object(ref_or_oid)
          add_without_check(HexaPDF::PDF::Object.new(nil, oid: obj.oid, gen: obj.gen))
        else
          @xref_section.delete(ref_or_oid)
          @objects.delete(ref_or_oid)
        end
      end

      # :call-seq:
      #   revision.each {|obj| block }   -> revision
      #   revision.each                  -> Enumerator
      #
      # Calls the given block once for every object of the revision.
      #
      # Objects that are loadable via an associated cross-reference section but are currently not, are
      # loaded automatically.
      def each(&block)
        load_all_objects
        each_available(&block)
      end

      # :call-seq:
      #   revision.each_available {|obj| block }   -> revision
      #   revision.each_available                  -> Enumerator
      #
      # Calls the given block once for every available object of the revision.
      #
      # Objects that could be loaded from an associated cross-reference but which are currently not
      # loaded, are not included.
      def each_available
        return to_enum(__method__) unless block_given?
        @objects.each {|(_oid, _gen), data| yield(data)}
        self
      end

      private

      # Loads all objects from the associated cross-reference section.
      def load_all_objects
        return if defined?(@all_objects_loaded)
        @all_objects_loaded = true

        @xref_section.each do |(oid, _gen), data|
          next if @objects.entry?(oid)
          add_without_check(@parser.load_object(data))
        end
      end

      # Adds the object to the available objects of this revision and returns it.
      def add_without_check(obj)
        @objects[obj.oid, obj.gen] = obj
      end

    end

  end
end
