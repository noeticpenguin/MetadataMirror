#!/usr/bin/env ruby

require 'metaforce'

#detailTypes = ["ApexClass", "ApexComponent", "ApexPage", "ApexTrigger", "CustomApplication", "CustomObject",
#        "CustomTab", "Layout", "Profile", "Queue", "RemoteSiteSetting", "StaticResource", "Workflow"]

#itemsToReview = ["CustomObjectTranslation", "CustomSite", "HomePageLayout", "PermissionSet", "ApexClass", "Role"]


# Define some constants

METAFORCE_CONFIG_FILE_PATH = ".metaforce.yml"
TYPE_CACHE_FILE_NAME = "./typeCache.yaml"
TYPE_MEMBERS_CACHE_FILE_NAME = "./typeMembersCache.yaml"
METADATA_WORKING_DIRECTORY = "/home/alex/dev/RubySandbox/SfOrgRetrieveAll/src/"


# Define a bunch of useful methods. Will call these at the bottom of the file.

def createClient()
    Metaforce.configuration.log = false

    target_org_name = "production"


    # Pull org credentials from a YAML file for now.
    config = YAML.load(File.read(METAFORCE_CONFIG_FILE_PATH))
    # {"production"=>{"username"=>"coolcat24@domain.com", "password"=>"som3p4ss", "security_token"=>"A23bG523dad"}, "developer"=>...}

    #if (target_org_name == "production")
    if (true)
        config_username = config[target_org_name][:username]
        config_password = config[target_org_name][:password]
        config_security_token = config[target_org_name][:security_token]
    end

    client = Metaforce.new :username => config_username, :password => config_password, :security_token => config_security_token
end



def fetchAllTypes(refresh_cache = false)
    types_hashie = {}

    # Use cache by default.
    if (File.exists?(TYPE_CACHE_FILE_NAME) and refresh_cache == false)
        types_hashie = YAML.load(File.read(TYPE_CACHE_FILE_NAME))
        return types_hashie
    end

    # Refresh metadata types from the SF org.
    client = createClient()
    describe_res = client.describe
    types_hashie = describe_res.metadata_objects.sort { |x,y| x.xml_name <=> y.xml_name }

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
    client = createClient()

    # Request members for each type.
    types_hashie.each do |type_desc|

        begin
            type_members_desc = client.list_metadata(type_desc.xml_name)
        rescue StandardError => err
            puts "caught exception on #{type_desc.xml_name}: #{err}"
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

    if (type_to_members_hash.nil?)
        return
    end

    type_to_members_hash.each do |type, members|
        puts "#{type.xml_name}"
        members.each do |member|
            puts "- #{member.full_name}" if member.respond_to?(:full_name)
        end
    end

end

def convertHashieToManifestHash(types_to_members_hashie)

    if (types_to_members_hashie.nil?)
        return
    end

    types_to_members_manifest_hash = {}

    # Convert the typeToMembersHash from a Hashie
    #   to a format that is suitable to give to Manifest.
    types_to_members_hashie.each_pair do |key, value|
        underscore_key = key.xml_name.underscore
        component_array = []

        # Get full_name array from an array...
        if (value.respond_to?("map"))
            component_array = value.map { |x| x.full_name if x.respond_to?("full_name") } unless value.nil?
        end
        # or a single value.
        if (value.respond_to?("full_name"))
            component_array = [] << value.full_name
        end

        types_to_members_manifest_hash[underscore_key] = component_array
    end

    return types_to_members_manifest_hash

end

def writePackageXml(type_to_members_manifest_hash)

    # Assuming parameter is properly formatted for the Manifest object.
    if (type_to_members_manifest_hash.nil?)
        return
    end

    manifest = Metaforce::Manifest.new(type_to_members_manifest_hash)

    File.open("package.xml", 'w') { |f| f.write(manifest.to_xml) }

end

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

#types_hashie = fetchAllTypes()

#types_to_members_hashie = appendMembersToTypesHashie(types_hashie)

#putsTypeMemberHashie(types_to_members_hashie)

#type_to_members_manifest_hash = convertHashieToManifestHash(types_to_members_hashie)

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




