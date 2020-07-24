# -*- encoding: utf-8; frozen_string_literal: true -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2020 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#
# If the GNU Affero General Public License doesn't fit your need,
# commercial licenses are available at <https://gettalong.at/hexapdf/>.
#++

require 'hexapdf/error'
require 'hexapdf/type/acro_form/variable_text_field'

module HexaPDF
  module Type
    module AcroForm

      # AcroForm text fields provide a box or space to fill-in data entered from keyboard. The text
      # may be restricted to a single line or can span multiple lines.
      #
      # == Type Specific Field Flags
      #
      # :multiline:: If set, the text field may contain multiple lines.
      #
      # :password:: The field is a password field. This changes the behaviour of the PDF reader
      #             application to not echo the input text and to not store it in the PDF file.
      #
      # :file_select:: The text field represents a file selection control where the input text is
      #                the path to a file.
      #
      # :do_not_spell_check:: The text should not be spell-checked.
      #
      # :do_not_scroll:: The text field should not scroll (horizontally for single-line fields and
      #                  vertically for multiline fields) to accomodate more text than fits into the
      #                  annotation rectangle. This means that no more text can be entered once the
      #                  field is full.
      #
      # :comb:: The field is divided into /MaxLen equally spaced positions (so /MaxLen needs to be
      #         set). This is useful, for example, when entering things like social security
      #         numbers which always have the same length.
      #
      # :rich_text:: The field is a rich text field.
      #
      # See: PDF1.7 s12.7.4.3
      class TextField < VariableTextField

        define_field :MaxLen, type: Integer

        # All inheritable dictionary fields for text fields.
        INHERITABLE_FIELDS = (superclass::INHERITABLE_FIELDS + [:MaxLen]).freeze

        # Updated list of field flags.
        FLAGS_BIT_MAPPING = superclass::FLAGS_BIT_MAPPING.merge(
          {
            multiline: 12,
            password: 13,
            file_select: 20,
            do_not_spell_check: 22,
            do_not_scroll: 23,
            comb: 24,
            rich_text: 25,
          }
        ).freeze

        # Returns the field value, i.e. the text contents of the field, or +nil+ if no value is set.
        #
        # Note that modifying the returned value *might not* modify the text contents in case it is
        # stored as stream! So always use #field_value= to set the field value.
        def field_value
          return unless value[:V]
          self[:V].kind_of?(String) ? self[:V] : self[:V].stream
        end

        # Sets the field value, i.e. the text contents of the field, to the given string.
        def field_value=(str)
          if flagged?(:password)
            raise HexaPDF::Error, "Storing a field value for a password field is not allowed"
          end
          self[:V] = str
        end

        # Returns the default field value.
        #
        # See: #field_value
        def default_field_value
          self[:DV].kind_of?(String) ? self[:DV] : self[:DV].stream
        end

        # Sets the default field value.
        #
        # See: #field_value=
        def default_field_value=(str)
          self[:DV] = str
        end

        # Creates appropriate appearance streams for all widgets.
        #
        # For information on how this is done see AppearanceGenerator.
        #
        # Note that an appearance stream for a text field widget is *always* created even if there
        # is an existing one to make sure the current field value is properly represented.
        def create_appearance_streams
          appearance_generator_class = document.config.constantize('acro_form.appearance_generator')
          each_widget do |widget|
            appearance_generator_class.new(widget).create_text_appearance_streams
          end
        end

        private

        def perform_validation #:nodoc:
          if field_type != :Tx
            yield("Field /FT of AcroForm text field has to be :Tx", true)
            self[:FT] = :Tx
          end

          super

          if self[:V] && !(self[:V].kind_of?(String) || self[:V].kind_of?(HexaPDF::Stream))
            yield("Text field doesn't contain text but #{self[:V].class} object")
          end
          if (max_len = self[:MaxLen]) && field_value.length > max_len
            yield("Text contents of field '#{full_field_name}' is too long")
          end
        end

      end

    end
  end
end
