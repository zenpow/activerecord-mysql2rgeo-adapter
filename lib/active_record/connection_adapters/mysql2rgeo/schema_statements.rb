module ActiveRecord
  module ConnectionAdapters
    module Mysql2Rgeo
      module SchemaStatements

        def indexes(table_name)
          indexes = []
          current_index = nil
          execute_and_free("SHOW KEYS FROM #{quote_table_name(table_name)}", "SCHEMA") do |result|
            each_hash(result) do |row|
              if current_index != row[:Key_name]
                next if row[:Key_name] == "PRIMARY" # skip the primary key
                current_index = row[:Key_name]

                mysql_index_type = row[:Index_type].downcase.to_sym
                case mysql_index_type
                when :fulltext, :spatial
                  index_type = mysql_index_type
                when :btree, :hash
                  index_using = mysql_index_type
                end

                indexes << [
                  row[:Table],
                  row[:Key_name],
                  row[:Non_unique].to_i == 0,
                  [],
                  lengths: {},
                  orders: {},
                  type: index_type,
                  using: index_using,
                  comment: row[:Index_comment].presence
                ]
              end

              indexes.last[-2] << row[:Column_name]
              indexes.last[-1][:lengths].merge!(row[:Column_name] => row[:Sub_part].to_i) if row[:Sub_part] && mysql_index_type != :spatial
              indexes.last[-1][:orders].merge!(row[:Column_name] => :desc) if row[:Collation] == "D"
            end
          end

          indexes.map { |index| IndexDefinition.new(*index) }
        end

        def type_to_sql(type, limit: nil, precision: nil, scale: nil, unsigned: nil, **) # :nodoc:
          if (info = RGeo::ActiveRecord.geometric_type_from_name(type.to_s.delete("_")))
            type = limit[:type] || type if limit.is_a?(::Hash)
            type = :geometry if type.eql? :spatial
            type = type.to_s.delete("_").upcase
          end
          super
        end

        # override
        def native_database_types
          # Add spatial types
          super.merge(
            geometry: { name: "geometry" },
            point: { name: "point" },
            linestring: { name: "linestring" },
            polygon: { name: "polygon" },
            multi_geometry: { name: "geometrycollection" },
            multi_point: { name: "multipoint" },
            multi_linestring: { name: "multilinestring" },
            multi_polygon: { name: "multipolygon" },
            spatial: { name: "geometry", limit: { type: :point } }
          )
        end

        # override
        def create_table_definition(*args)
          Mysql2Rgeo::TableDefinition.new(*args)
        end

        def initialize_type_map(m = type_map)
          super
          %w(
            geometry
            point
            linestring
            polygon
            geometrycollection
            multipoint
            multilinestring
            multipolygon
          ).each do |geo_type|
            m.register_type(geo_type, Type::Spatial.new(geo_type))
          end
        end

        private

          def new_column_from_field(table_name, field)
            type_metadata = fetch_type_metadata(field[:Type], field[:Extra])
            if type_metadata.type == :datetime && /\ACURRENT_TIMESTAMP(?:\([0-6]?\))?\z/i.match?(field[:Default])
              default, default_function = nil, field[:Default]
            else
              default, default_function = field[:Default], nil
            end

            SpatialColumn.new(
              field[:Field],
              default,
              type_metadata,
              field[:Null] == "YES",
              table_name,
              default_function,
              field[:Collation],
              comment: field[:Comment].presence
            )
          end
      end
    end
  end
end
