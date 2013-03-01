#!/usr/bin/env ruby
# Always use bundler, as it will do a much better job of handling
# version dependency/conflicts
Bundler.require

#Ruby has idioms for creating Arrays like this, here's the "ruby" way:
# detail_types = %w{ApexClass ApexComponent ApexPage ApexTrigger CustomApplication CustomObject CustomTab, Layout Profile Queue RemoteSiteSetting StaticResource Worflow}
# why does this matter? eh, you could argue it doesn't but is a good habbit as it's more powerful than you might think.
# For exampe:
#   data_set = %w(Jason Jason Teresa Judah Michelle Judah Judah Allison)
#   words.inject(Hash.new(0)) { |total, e| total[e] += 1 ;total}
# gives us:
#   {"Jason"=>2, "Teresa"=>1, "Judah"=>3, "Michelle"=>1, "Allison"=>1}
# Now do that with a useful body of text -- say the constitution.

#itemsToReview = %w{CustomObjectTranslation CustomSite HomePageLayout PermissionSet ApexClass Role}


# Define some constants
METAFORCE_CONFIG_FILE_PATH = ".metaforce.yml"
TYPE_CACHE_FILE_NAME = "./typeCache.yaml"
TYPE_MEMBERS_CACHE_FILE_NAME = "./typeMembersCache.yaml"
METADATA_WORKING_DIRECTORY = "/home/alex/dev/RubySandbox/SfOrgRetrieveAll/src/"

# Define a bunch of useful methods. Will call these at the bottom of the file.

#idiomatic ruby style does not put () on def statments unless the method has input vars.
#also, always use snake_case for method names. CamelCase is used for objects.
def create_client
  Metaforce.configuration.log = false

  target_org_name = "production"

  # Pull org credentials from a YAML file for now.
  # Awesome use of YML and Constants.
  config = YAML.load(File.read(METAFORCE_CONFIG_FILE_PATH))
  # {"production"=>{"username"=>"coolcat24@domain.com", "password"=>"som3p4ss", "security_token"=>"A23bG523dad"}, "developer"=>...}

  #if (target_org_name == "production")
  # This is a hard habit to break, but if statements with ()'s are a code smell in ruby.
  # They're only ever needed for complex conditionals and ruby has better ways of handling them.
  #
  if (true)
    config_username = config[target_org_name][:username]
    config_password = config[target_org_name][:password]
    config_security_token = config[target_org_name][:security_token]
  end

  # You probably wants this to be a class var.
  @client = Metaforce.new :username => config_username, :password => config_password, :security_token => config_security_token
end

def fetch_all_types(refresh_cache = false)
  #you don't need to predefine this, YAML.load returns a hash.
  # types_hashie = {}

  # Use cache by default.
  if (File.exists?(TYPE_CACHE_FILE_NAME) and refresh_cache == false)
    types_hashie = YAML.load(File.read(TYPE_CACHE_FILE_NAME))
    types_hashie #return keyword is almost never used. ruby returns the last evaluated statement
  end

  # Refresh metadata types from the SF org.
  @client ||= create_client
  types_hashie = client.describe.metadata_objects.sort { |x,y| x.xml_name <=> y.xml_name }

  # Cache results for next time.
  File.open(TYPE_CACHE_FILE_NAME, 'w') { |f| f.write(YAML.dump(types_hashie)) }

  return types_hashie
end

def appendMembersToTypesHashie(types_hashie = {}, refresh_cache = false)

  type_to_members_hash = {}

  # Use cache by default.
  if (File.exists?(TYPE_MEMBERS_CACHE_FILE_NAME) and refresh_cache == false)
    type_to_members_hash = YAML.load(File.read(TYPE_MEMBERS_CACHE_FILE_NAME))
    return type_to_members_hash
  end

  # Refresh metadata members from the SF org.
  client ||= createClient()

  # Request members for each type.
  types_hashie.each do |type_desc|
    begin
      type_members_desc = client.list_metadata(type_desc.xml_name)
    rescue StandardError => err
      #in the gemfile I snuck in awesome_print.
      #it's a gem that is quite useful for error output
      #it nicely formats hash's, arrays and objects etc. try this:
      ap "caught exception on #{type_desc.xml_name}: #{err}"
      type_members_desc = {}
    end

    #puts "sorting members=#{type_members_desc}"
    type_members_desc_sorted = type_members_desc.sort do |x,y|
      result = 0
      if (x.respond_to?("full_name"))
        result = x.full_name.downcase <=> y.full_name.downcase
      end
      result
    end

    type_to_members_hash[type_desc] = type_members_desc_sorted

  end

  #puts type_members_desc
  #sorted = type_members_desc.sort { |x,y| x.full_name <=> y.full_name }

  # Cache results for next time.
  File.open(TYPE_MEMBERS_CACHE_FILE_NAME, 'w') { |f| f.write(YAML.dump(type_to_members_hash)) }

  return type_to_members_hash
end

def putsTypeMemberHashie(type_to_members_hash = {})

  #time for some ruby fu. Ruby can use predicate conditionals which look like this:
  # x = y if foo
  # OR
  # x = y unless foo.nil?
  # Thus:
  return if type_to_members_hash.nil?

  type_to_members_hash.each do |type, members|
    puts "#{type.xml_name}"
    members.each do |member|
      puts "- #{member.full_name}" if member.respond_to?(:full_name)
    end
  end
end

def convertHashieToManifestHash(types_to_members_hashie)

  return if types_to_members_hashie.nil?
  types_to_members_manifest_hash = {}

  # Convert the typeToMembersHash from a Hashie
  # to a format that is suitable to give to Manifest.
  types_to_members_hashie.each_pair do |key, value|
    underscore_key = key.xml_name.underscore
    component_array = []

    # Get full_name array from an array...
    component_array = value.map { |x| x.full_name if x.respond_to?("full_name") } unless value.nil? AND value.respond_to?("map")
    # or a single value.
    if (value.respond_to?("full_name"))
      #I didn't know you could do that (below) but it works... Normally we do:
      component_array = [value.full_name]
      # component_array = [] << value.full_name
    end

    types_to_members_manifest_hash[underscore_key] = component_array
  end

  types_to_members_manifest_hash

end

def writePackageXml(type_to_members_manifest_hash)
  return if type_to_members_manifest_hash.nil?
  # Assuming parameter is properly formatted for the Manifest object.
  manifest = Metaforce::Manifest.new(type_to_members_manifest_hash)

  #I'm pretty sure you'll need:
  manifest_data = manifest.to_pacakge

  # :parse might not be the right method, but check somethign, to ensure you're not writing 
  # bogus stuff to package.xml
  File.open("package.xml", 'w') { |f| f.write(manifest_data) } if manifest.respond_to? :parse 
end


###
## Stopped after this line because it appears these methods were to be refactored out?
###
###
## General Notes:
###
#
# This should be a class. Better yet, this should be a Thor setup.
# Thor is a "command line app" framework. 
# whenever you invoke rails * you're calling a thor app. 
# Thor gives you a handy way of invoking a class such as this
# in a nice command line runner.
# At the least, you should make this a class, perhaps:
# 

class MetadataMirror 

# your methods go here.

end

#then, after the class:
#
# instance = MetadataMirror.new
# instance.method1
# instance.method2
# instance.dot_dot_dot
# instance.profit!
# 
# why? well, if you're going to re-use this code, build it as a class now.

# Consider removing this,
# Separated this into `convertHashieToManifestHash` and `writePackageXml`.
def writePackageXmlFromHashie(typeToMembersHash = {})

  typeToMembersHashFormatted = {}

  # Assuming parameter is a Hashie object.
  #puts typeToMembersHash.keys

  # Convert the typeToMembersHash from a Hashie
  #   to a format that is suitable to give to Manifest.
  typeToMembersHash.each_pair do |key, value|
    underscore_key = key.xml_name.underscore
    #puts "key=#{underscore_key}, value=#{value}"
    component_array = []
    if (value.respond_to?("map"))
      component_array = value.map { |x| x.full_name if x.respond_to?("full_name") } unless value.nil?
    end
    if (value.respond_to?("full_name"))
      component_array = [] << value.full_name
    end
    #puts "valArray=#{component_array}"

    typeToMembersHashFormatted[underscore_key] = component_array

  end

  #puts typeToMembersHashFormatted
  manifest = Metaforce::Manifest.new(typeToMembersHashFormatted)
  #manifest.to_xml

  File.open("package.xml", 'w') { |f| f.write(manifest.to_xml) }

end





# Now we can use the helpful functions.

types_hashie = fetch_all_types()

types_to_members_hashie = appendMembersToTypesHashie(types_hashie)

putsTypeMemberHashie(types_to_members_hashie)

type_to_members_manifest_hash = convertHashieToManifestHash(types_to_members_hashie)

#writePackageXml(type_to_members_manifest_hash)

#writePackageXmlFromHashie(types_to_members_hashie)




# Now that we can make a full manifest of the SF org,
#   let's pull down the entire org's metadata.

#manifest = Metaforce::Manifest.new(type_to_members_manifest_hash)

client = createClient()
#client.retrieve_unpackaged(manifest)
#    .on_complete { |job| puts "Retrieve Completed: #{job.id}." }
#    .on_error { |job| puts "Retrieve Failed: #{job.id}." }
#    .on_poll { |job| puts "...polling... #{job.inspect}" }
#    .extract_to(METADATA_WORKING_DIRECTORY)
#    .perform
