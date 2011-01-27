module Neo4j
  module Batch

    # = Batch Insert
    # Neo4j has a batch insert mode that drops support for transactions and concurrency in favor of insertion speed.
    # This is useful when you have a big dataset that needs to be loaded once. In our experience, the batch inserter will
    # typically inject data around five times faster than running in normal transactional mode.
    #
    # Be aware that the BatchInserter is intended use is for initial import of data
    # * non thread safe
    # * non transactional
    # * failure to successfully invoke shutdown (properly) results in corrupt database files
    #
    # == Usage
    #
    #  === Nodes/Properties and Relationships
    #
    #  Example:
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config)
    #
    #    node_a = inserter.create_node(:name => 'andreas')
    #    node_c = inserter.create_node(:name => 'craig')'
    #
    #    inserter.create_rel(:friends, node_a, node_c, :since => '2009')
    #
    # node_a and node_b are simply Fixnum objects
    #
    #  === Index, Neo4j::Node
    #
    #  Let say you have declared the following index
    #
    #    Neo4j::Node.index :name
    #
    #  You can now add lucene index using the batch inserter, example:
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config)
    #    node_a = inserter.create_node(:name => 'andreas')
    #    inserter.index(node_a, :name => 'andreas')'
    #
    #  The Inserter#index method will add index of all declared indexes declared type (default 'exact')
    #
    #  === Index on NodeMixin or Model
    #
    #  The Inserter#index indexes on default Neo4j::Node object.
    #  Example of adding an index on a NodeMixin class using batch inserter:
    #
    #    class Person
    #      include Neo4j::NodeMixin
    #      index :desc => :fulltext
    #    end
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config)
    #    node_a = inserter.create_node(:name => 'andreas')
    #    inserter.index(node_a, :name => 'andreas', Person)'
    #
    # === NodeMixin and  _classname
    #
    #  Example:
    #
    #    class Person
    #      include Neo4j::NodeMixin
    #    end
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config)
    #    person_inserter = inserter.for_class(Person)
    #
    #    node_a = person_inserter.create_node(:name => 'andreas')
    #    node_c = person_inserter.create_node(:name => 'craig')'
    #
    #  This will add the '_classname' property' needed for mapping nodes to Ruby classes.
    #
    # === NodeMixin and has_n
    #
    # Example:
    #
    #    class Person
    #      include Neo4j::NodeMixin
    #      has_n(:friends).to(Person)
    #    end
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config, Person)
    #    person_inserter = inserter.for_class(Person)
    #
    #    node_a = person_inserter.create_node(:name => 'andreas')
    #    node_c = person_inserter.create_node(:name => 'craig')'
    #
    #    person_inserter.create_rel(node_a, node_b, :friends, :since => '2009')
    #
    #  This create a relationship of type 'Person#friend' from node_a to node_b
    #
    # === Using the index, TODO !!!
    #
    # After the #optimize_index has been call one can use the index to find nodes
    #
    # Example
    #  
    #    inserter = Neo4j::Batch::Inserter.new(storage, config, Person)
    #    person_inserter = inserter.for_class(Person)
    #
    #    # insert and index lots of nodes
    #    person_inserter.optimize_index
    #    node_a = person_inserter.find(:name, 'andreas').first
    #    node_b = person_inserter.find(:name, 'craig').first
    #    person_inserter.create_rel(node_a, node_b, :friends, :since => '2009')
    #
    #
    # === Shutdown
    # 
    # Example:
    #
    #    inserter = Neo4j::Batch::Inserter.new(storage, config, Person)
    #    person_inserter = inserter.for_class(Person)
    #
    #    # lots of insert/index operations
    #    inserter.shutdown
    #
    #  The shutdown method will also shutdown all index inserters.
    #  Notice, failing to invoke the shutdown method may corrupt the store !
    #  
    class Inserter
      attr_reader :batch_inserter, :batch_indexer
      include ToJava

      # Creates a new batch inserter.
      # Will raise an exception if Neo4j is already running at the same storage_path
      # 
      def initialize(storage_path=Neo4j.config.storage_path, config={})
        # check if neo4j is running and using the same storage path
        raise "Not allowed to start batch inserter while Neo4j is already running at storage location #{storage_path}" if Neo4j.storage_path == storage_path
        @batch_inserter  = org.neo4j.kernel.impl.batchinsert.BatchInserterImpl.new(storage_path, config)

        Indexer.index_provider  = org.neo4j.index.impl.lucene.LuceneBatchInserterIndexProvider.new(@batch_inserter)
        Indexer.inserter        = @batch_inserter
      end

      def running?
        @batch_inserter != nil
      end

      # This method MUST be called after inserting is completed.
      def shutdown
        @batch_inserter && @batch_inserter.shutdown
        @batch_inserter = nil

        Indexer.index_provider
        Indexer.index_provider && Indexer.index_provider.shutdown
        Indexer.index_provider = nil
        Indexer.inserter = nil
      end

      # Creates a node. Returns a Fixnum id of the created node. 
      def create_node(hash=nil)
        @batch_inserter.create_node(hash)
      end

      # returns true if the node exists
      def node_exist?(id)
        @batch_inserter.node_exists(id)
      end

      def ref_node
        @batch_inserter.get_reference_node
      end

      # creates a relationship between given nodes of given type.
      # Returns a fixnum id of the created relationship.
      def create_rel(type, from_node, to_node, property_hash=nil)
        @batch_inserter.createRelationship(from_node, to_node, type_to_java(type), property_hash)
      end

      # Return a hash of all properties of given node
      def node_props(node)
        @batch_inserter.get_node_properties(node)
      end

      # Sets the properties of the given node, overwrites old properties
      def set_node_props(node, hash)
        @batch_inserter.set_node_properties(node, hash)
      end

      # Sets the old properties of the given relationship, overwrites old properties
      def set_rel_props(rel, hash)
        @batch_inserter.set_relationship_properties(rel, hash)
      end

      # Returns the properties of the given relationship
      def rel_props(rel)
        @batch_inserter.get_relationship_properties(rel)
      end
      
      # Returns all the relationships of the given node
      def rels(node)
        @batch_inserter.getRelationships(node)
      end

      # index the given entity (a node or a relationship)
      def index(entity, props, clazz = Neo4j::Node)
        indexer = Indexer.instance_for(clazz)
        indexer.index_entity(entity, props)
      end


      # hmm, maybe faster not wrapping this ?
      def to_java_map(hash)
        return nil if hash.nil?
        map = java.util.HashMap.new
        hash.each_pair do |k, v|
          case v
            when Symbol
              map[k.to_s] = v.to_s
            else
              map[k.to_s] = v
          end
        end
        map
      end
    end
  end
end