class ActiveRecord::Base
  module DeepCloneable
    def self.included(base)
      base.alias_method_chain :clone, :deep_cloning
    end

    # clones an ActiveRecord model. 
    # if passed the :include option, it will deep clone the given associations
    # if passed the :except option, it won't clone the given attributes
    #
    # === Usage:
    # 
    # ==== Cloning one single association
    #    pirate.clone :include => :mateys
    # 
    # ==== Cloning multiple associations
    #    pirate.clone :include => [:mateys, :treasures]
    # 
    # ==== Cloning really deep
    #    pirate.clone :include => {:treasures => :gold_pieces}
    # 
    # ==== Cloning really deep with multiple associations
    #    pirate.clone :include => [:mateys, {:treasures => :gold_pieces}]
    #
    # ==== Cloning really deep with multiple associations and a dictionary
    #
    # A dictionary ensures that models are not cloned multiple times when it is associated to nested models. 
    # When using a dictionary, ensure recurring associations are cloned first:
    #
    #    pirate.clone :include => [:mateys, {:treasures => [:matey, :gold_pieces], :use_dictionary => true }]    
    #
    # If this is not an option for you, it is also possible to populate the dictionary manually in advance:
    #
    #    dict = { :mateys => {} }
    #    pirate.mateys.each{|m| dict[:mateys][m] = m.clone }
    #    pirate.clone :include => [:mateys, {:treasures => [:matey, :gold_pieces], :dictionary => dict }]    
    #   
    # ==== Cloning a model without an attribute
    #    pirate.clone :except => :name
    #  
    # ==== Cloning a model without multiple attributes
    #    pirate.clone :except => [:name, :nick_name]
    #    
    # ==== Cloning a model without an attribute or nested multiple attributes   
    #    pirate.clone :include => :parrot, :except => [:name, { :parrot => [:name] }]
    # 
    def clone_with_deep_cloning(options = {})
      dict = options[:dictionary]
      dict ||= {} if options.delete(:use_dictionary)

      kopy = unless dict
        clone_without_deep_cloning
      else
        tableized_class = self.class.name.tableize.to_sym
        dict[tableized_class] ||= {}
        dict[tableized_class][self] ||= clone_without_deep_cloning
      end

      deep_exceptions = {}
      if options[:except]
        exceptions = options[:except].nil? ? [] : [options[:except]].flatten
        exceptions.each do |attribute|
          kopy.send(:write_attribute, attribute, attributes_from_column_definition[attribute.to_s]) unless attribute.kind_of?(Hash)
        end
        deep_exceptions = exceptions.select{|e| e.kind_of?(Hash) }.inject({}){|m,h| m.merge(h) }
        kopy.instance_variable_set(:@changed_attributes, {})
      end

      if options[:include]
        Array(options[:include]).each do |association, deep_associations|
          if (association.kind_of? Hash)
            deep_associations = association[association.keys.first]
            association = association.keys.first
          end

          opts = deep_associations.blank? ? {} : {:include => deep_associations}
          opts.merge!(:except => deep_exceptions[association]) if deep_exceptions[association]
          opts.merge!(:dictionary => dict) if dict

          association_reflection = self.class.reflect_on_association(association)
          raise AssociationNotFoundException.new("#{self.class}##{association}") if association_reflection.nil?

          case association_reflection.macro
          when :belongs_to, :has_one
            clone = self.send(association) && self.send(association).clone(opts)
            kopy.send("build_#{association}", clone.attributes) if clone
          when :has_many, :has_and_belongs_to_many
            reverse_association_name = association_reflection.klass.reflect_on_all_associations.detect do |a|
              a.primary_key_name.to_s == association_reflection.primary_key_name.to_s
            end.try(:name)

            self.send(association).each do |obj|
              tmp = obj.clone(opts)
              tmp.send("#{association_reflection.primary_key_name.to_s}=", nil)
              tmp.send("#{reverse_association_name.to_s}=", kopy) if reverse_association_name
              kopy.send("#{association}").send(:<<, tmp)
            end
          end
        end
      end

      kopy
    end

    class AssociationNotFoundException < StandardError; end    
  end

  include DeepCloneable
end