require_relative 'utils'
require 'securerandom'

Sequel.migration do

  up do
    self.transaction do

      # FIXME add I18n for en, es, fr for new fields and enums
      # FIXME remove I18n for en, es, fr for removed fields and enums

      # #######################################################################
      # Add new rights_statement_act table
      #
      create_table(:rights_statement_act) do
        primary_key :id

        Integer :rights_statement_id, :null => false
        DynamicEnum :act_type_id, :null => false
        DynamicEnum :restriction_id, :null => false
        Date :start_date, :null => false
        Date :end_date, :null => true

        apply_mtime_columns
      end

      alter_table(:rights_statement_act) do
        add_foreign_key([:rights_statement_id], :rights_statement, :key => :id)
      end

      create_editable_enum("rights_statement_act_type",
                    ['delete', 'disseminate', 'migrate', 'modify', 'replicate', 'use'])

      create_editable_enum("rights_statement_act_restriction",
                           ['allow', 'disallow', 'conditional'])

      alter_table(:note) do
        add_column(:rights_statement_act_id, Integer,  :null => true)
        add_foreign_key([:rights_statement_act_id], :rights_statement_act, :key => :id)
      end

      create_enum("note_rights_statement_act_type",
                  ['permissions', 'restrictions', 'extension', 'expiration'])

      # #######################################################################
      # Link rights_statement to agents
      #
      alter_table(:linked_agents_rlshp) do
        add_column(:rights_statement_id, Integer,  :null => true)
        add_foreign_key([:rights_statement_id], :rights_statement, :key => :id)
      end

      # #######################################################################
      # Link rights_statement to notes
      #
      alter_table(:note) do
        add_column(:rights_statement_id, Integer,  :null => true)
        add_foreign_key([:rights_statement_id], :rights_statement, :key => :id)
      end

      create_enum("note_rights_statement_type",
           ['materials', 'type_note', 'additional_information'])

      # #######################################################################
      # Add 'Identifier Type' to external documents
      #
      alter_table(:note) do
        add_column(:identifier_type_id, Integer, :null => true)
        add_foreign_key([:identifier_type_id], :enumeration_value, :key => :id, :name => 'external_document_identifier_type_id_fk')
      end
      # FIXME real enum values
      create_editable_enum('rights_statement_external_document_identifier_type',
                           ['test_a', 'test_b'])

      # #######################################################################
      # Add new rights_statement columns
      #
      alter_table(:rights_statement) do
        add_column(:status_id, Integer,  :null => true)
        add_column(:start_date, Date, :null => true)
        add_column(:end_date, Date, :null => true)
        add_column(:determination_date, Date, :null => true)
        add_column(:license_terms, String, :null => true)
        add_column(:other_rights_basis_id, Integer, :null => true)

        add_foreign_key([:status_id], :enumeration_value, :key => :id, :name => 'rights_statement_status_id_fk')
        add_foreign_key([:other_rights_basis_id], :enumeration_value, :key => :id, :name => 'rights_statement_other_rights_basis_id_fk')
      end

      create_editable_enum('rights_statement_other_rights_basis',
                           ['donor', 'policy'])


      # #######################################################################
      # Migrate from old to new
      #
      # - Populate a meaningful start_date for rights statements
      # FIXME need to map a start_date as is now mandatory for all types
      # FIXME derive start_date from outer record 'creation' begin date
      # FIXME or from outer record create timestamp

      # - Rights types coded as "Intellectual Property" should be converted to
      #   "Copyright", and Rights types coded as "Institutional Policy"
      #   should be converted to "Other".
      rights_type_enum_id = self[:enumeration]
                              .filter(:name => 'rights_statement_rights_type')
                              .select(:id)

      self[:enumeration_value]
        .filter(:enumeration_id => rights_type_enum_id)
        .filter(:value => 'intellectual_property')
        .update(:value => 'copyright')

      self[:enumeration_value]
        .filter(:enumeration_id => rights_type_enum_id)
        .filter(:value => 'institutional_policy')
        .update(:value => 'other')

      # - Migrate data currently encoded in "IP Expiration Date" on the
      #   "Intellectual Property" template to "End Date" on the Copyright
      #   template
      self[:rights_statement]
        .filter(Sequel.~(:ip_expiration_date => nil))
        .update(:end_date => :ip_expiration_date)

      #  - When a rights type is converted from "Institutional Policy" to
      #    "Other", the "Other Rights Basis" value should be "Institutional
      #    Policy"
      other_rights_basis_enum = self[:enumeration]
                                  .filter(:name => 'rights_statement_other_rights_basis')
                                  .select(:id)
      policy_enum_id = self[:enumeration_value]
                         .filter(:enumeration_id => other_rights_basis_enum)
                         .filter(:value => 'policy')
                         .select(:id)
      other_type_id = self[:enumeration_value]
                        .filter(:enumeration_id => rights_type_enum_id)
                        .filter(:value => 'other')
                        .select(:id)
      self[:rights_statement]
        .filter(:rights_type_id => other_type_id)
        .update(:other_rights_basis_id => policy_enum_id)

      # - All data currently included in the "Materials" element should be
      #   migrated to the note with the label "Materials".
      self[:rights_statement]
        .filter(Sequel.~(:materials => nil))
        .select(:id, :materials, :last_modified_by, :create_time, :system_mtime, :user_mtime)
        .each do |row|
        self[:note].insert(
          :rights_statement_id => row[:id],
          :publish => 1,
          :notes_json_schema_version => 1,
          :notes => ASUtils.to_json({
            'jsonmodel_type' => 'note_rights_statement',
            'content' => [row[:materials]],
            'type' => 'materials',
            'persistent_id' => SecureRandom.hex
          }),
          :last_modified_by => row[:last_modified_by],
          :create_time => row[:create_time],
          :system_mtime => row[:system_mtime],
          :user_mtime => row[:user_mtime]
        )
      end

      # - Also, all data currently included in the "Type" note should be
      # migrated to the note with the label "Type".
      self[:rights_statement]
        .filter(Sequel.~(:type_note => nil))
        .select(:id, :type_note, :last_modified_by, :create_time, :system_mtime, :user_mtime)
        .each do |row|
        self[:note].insert(
          :rights_statement_id => row[:id],
          :publish => 1,
          :notes_json_schema_version => 1,
          :notes => ASUtils.to_json({
                                      'jsonmodel_type' => 'note_rights_statement',
                                      'content' => [row[:type_note]],
                                      'type' => 'type_note',
                                      'persistent_id' => SecureRandom.hex
                                    }),
          :last_modified_by => row[:last_modified_by],
          :create_time => row[:create_time],
          :system_mtime => row[:system_mtime],
          :user_mtime => row[:user_mtime]
        )
      end

      # - Migrate data currently encoded in "Granted Note" to an Act note
      #   sub-record with Label = "Additional Information"
      # FIXME confirm this is to an Act or Rights Statement note?
      # Assuming Rights Statement note currently...
      self[:rights_statement]
        .filter(Sequel.~(:granted_note => nil))
        .select(:id, :granted_note, :last_modified_by, :create_time, :system_mtime, :user_mtime)
        .each do |row|
        self[:note].insert(
          :rights_statement_id => row[:id],
          :publish => 1,
          :notes_json_schema_version => 1,
          :notes => ASUtils.to_json({
                                      'jsonmodel_type' => 'note_rights_statement',
                                      'content' => [row[:granted_note]],
                                      'type' => 'additional_information',
                                      'persistent_id' => SecureRandom.hex
                                    }),
          :last_modified_by => row[:last_modified_by],
          :create_time => row[:create_time],
          :system_mtime => row[:system_mtime],
          :user_mtime => row[:user_mtime]
        )
      end

      # - Migrate data currently encoded in "Permissions" to an Act note
      #   sub-record with Label = "Permissions".
      # FIXME confirm how act mandatory fields are mapped
      # FIXME fallback to start_date from outer rights statement start_date
      act_type_use_id = self[:enumeration_value]
                          .filter(:value => 'use')
                          .filter(:enumeration_id => self[:enumeration].filter(:name => 'rights_statement_act_type').select(:id))
                          .select(:id)
                          .first[:id]

      restriction_allow_id = self[:enumeration_value]
                               .filter(:value => 'allow')
                               .filter(:enumeration_id => self[:enumeration].filter(:name => 'rights_statement_act_restriction').select(:id))
                               .select(:id)
                               .first[:id]

      self[:rights_statement]
        .filter(Sequel.~(:permissions => nil))
        .select(:id, :permissions, :restriction_start_date, :restriction_end_date,
                :last_modified_by, :create_time, :system_mtime, :user_mtime)
        .each do |row|
        act_id = self[:rights_statement_act]
                  .insert(
                    :rights_statement_id => row[:id],
                    :act_type_id => act_type_use_id,
                    :restriction_id => restriction_allow_id,
                    :start_date => row[:restriction_start_date] || row[:create_time].strftime('%y-%m-%d'),
                    :end_date => row[:restriction_end_date],
                    :last_modified_by => row[:last_modified_by],
                    :create_time => row[:create_time],
                    :system_mtime => row[:system_mtime],
                    :user_mtime => row[:user_mtime])

        self[:note]
          .insert(
            :rights_statement_act_id => act_id,
            :publish => 1,
            :notes_json_schema_version => 1,
            :notes => ASUtils.to_json({
                                        'jsonmodel_type' => 'note_rights_statement_act',
                                        'content' => [row[:permissions]],
                                        'type' => 'permissions',
                                        'persistent_id' => SecureRandom.hex
                                      }),
            :last_modified_by => row[:last_modified_by],
            :create_time => row[:create_time],
            :system_mtime => row[:system_mtime],
            :user_mtime => row[:user_mtime])
      end

      # - Migrate data currently encoded in "Restrictions" to an Act note
      #   sub-record with Label = "Restrictions".
      # FIXME confirm how act mandatory fields are mapped
      restriction_disallow_id = self[:enumeration_value]
                                  .filter(:value => 'disallow')
                                  .filter(:enumeration_id => self[:enumeration].filter(:name => 'rights_statement_act_restriction').select(:id))
                                  .select(:id)
                                  .first[:id]

      self[:rights_statement]
        .filter(Sequel.~(:restrictions => nil))
        .select(:id, :restrictions, :restriction_start_date, :restriction_end_date,
                :last_modified_by, :create_time, :system_mtime, :user_mtime)
        .each do |row|
        act_id = self[:rights_statement_act]
                  .insert(
                    :rights_statement_id => row[:id],
                    :act_type_id => act_type_use_id,
                    :restriction_id => restriction_disallow_id,
                    :start_date => row[:restriction_start_date] || row[:create_time].strftime('%y-%m-%d'),
                    :end_date => row[:restriction_end_date],
                    :last_modified_by => row[:last_modified_by],
                    :create_time => row[:create_time],
                    :system_mtime => row[:system_mtime],
                    :user_mtime => row[:user_mtime])

        self[:note]
          .insert(
            :rights_statement_act_id => act_id,
            :publish => 1,
            :notes_json_schema_version => 1,
            :notes => ASUtils.to_json({
                                        'jsonmodel_type' => 'note_rights_statement_act',
                                        'content' => [row[:restrictions]],
                                        'type' => 'restrictions',
                                        'persistent_id' => SecureRandom.hex
                                      }),
            :last_modified_by => row[:last_modified_by],
            :create_time => row[:create_time],
            :system_mtime => row[:system_mtime],
            :user_mtime => row[:user_mtime])
      end

      # - Migrate data currently encoded in "Restrictions Start Date" to
      #   "Act Start Date"
      # FIXME should we map these dates if there's no note? and what should the
      # mandatory fields be set to?

      # - Migrate data currently encoded in "Restrictions End Date" to
      #   "Act End Date"
      # FIXME should we map these dates if there's no note? and what should the
      # mandatory fields be set to?

      # #######################################################################
      # Remove the old columns. NO TURNING BACK NOW! WEEEEEEEEEEEEEEEEEEEEEEEE
      #
      alter_table(:rights_statement) do
        # drop fks
        drop_foreign_key [:ip_status_id], :name => :rights_statement_ibfk_2

        # drop columns
        drop_column(:active)
        drop_column(:ip_status_id)
        drop_column(:restriction_start_date)
        drop_column(:restriction_end_date)
        drop_column(:materials)
        drop_column(:ip_expiration_date)
        drop_column(:type_note)
        drop_column(:permissions)
        drop_column(:restrictions)
        drop_column(:granted_note)
        drop_column(:license_identifier_terms)
      end
    end
  end

  down do
  end

end
