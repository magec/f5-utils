#!/usr/bin/env ruby
module F5Utils

  class << self
    attr_accessor :logger
  end 

  @logger =  Logger.new(STDOUT)

  class VirtualServer
    
    def self.find_free_port(ip_address)
      virtual_servers = IControl::LocalLB::VirtualServer.find(:all)
      same_ip_virtual_servers = virtual_servers.select { |i| i.destination.address == ip_address }
      ports = same_ip_virtual_servers.map{|i| i.destination.port}
      free_port = 1
      while ports.include? free_port.to_s
        free_port +=1
      end
      free_port
    end
    
    def self.rename(source,target)

      self.copy(source,target)

      source_virtual_server = IControl::LocalLB::VirtualServer.find(source)

      source_destination =  source_virtual_server.destination

      aux = source_destination.port 
      source_destination.port = find_free_port(source_destination.address)

      begin
        F5Utils.logger.info("Changing the port of the source virtual server to #{source_destination.port}")        
        source_virtual_server.destination= source_destination
      rescue
        puts $!.inspect
        source_destination.port = aux
        source_virtual_server.destination= source_destination
        exit 1
      end
      target_destination = target_virtual_server.destination
      target_destination.port = aux
      F5Utils.logger.info("Changing the port of the target virtual server to its actual value")
      target_virtual_server.destination = target_destination

      target_virtual_server.default_persistence_profile = target_virtual_server.persistence_profile

      F5Utils.logger.info("Done")

      F5Utils.logger.info("Deleting the source virtual server")
      source_virtual_server.destroy
    end
    
    def self.copy(source,target,options = {})
      unless source_virtual_server = IControl::LocalLB::VirtualServer.find(source)
        puts "Error, no such virtual server (#{source})"
        exit 1
      end
      if p = IControl::LocalLB::VirtualServer.find(target)
        puts "Error, target virtual server already exists"
        exit 1
      end
      unless target
        puts "Error, target not specified"
        exit 0
      end
      
      F5Utils.logger.info("Creating a new virtual server copy of the previous one but listening in another port")
      source_destination =  source_virtual_server.destination

      if options[:address] || options[:port]

        if options[:address] 
          ip_dest= options[:address] 
          port_dest = options[:port] || source_destination.port
        end
        
        if options[:port]
          ip_dest=  options[:address] || source_destination.address
          port_dest = options[:port]
        end

      else

        ip_dest = source_destination.address
        port_dest = find_free_port(source_destination.port)

      end
      
      F5Utils.logger.debug("Name:              #{target}")
      F5Utils.logger.debug("IP:                #{ip_dest}")
      F5Utils.logger.debug("Port:              #{port_dest}")
      F5Utils.logger.debug("Protocol:          #{source_virtual_server.protocol.to_s}")
      F5Utils.logger.debug("Wildmask:          #{source_virtual_server.wildmask.inspect}")
      F5Utils.logger.debug("Type:              #{source_virtual_server.type.to_s}")
      F5Utils.logger.debug("Default Pool Name: #{source_virtual_server.default_pool.id if source_virtual_server.default_pool}")
      F5Utils.logger.debug("Profiles:          #{source_virtual_server.profiles.map{|i| i.inspect}.join(",")}")
      
      begin
        target_virtual_server = IControl::LocalLB::VirtualServer.create(:name => target,
                                                                        :address => ip_dest,
                                                                        :port => port_dest,
                                                                        :protocol => source_virtual_server.protocol,
                                                                        :wildmask => source_virtual_server.wildmask,
                                                                        :type => source_virtual_server.type,
                                                                        :default_pool =>  source_virtual_server.default_pool,
                                                                        :profiles => source_virtual_server.profiles)
        F5Utils.logger.debug("Setting attributes")

        # Savon::Request.log = true

        fields = ["default_pool","persistence_profile","fallback_persistence_profile",
                  "snat_type","vlan","rate_class","connection_mirror_state","connection_limit",
                  "translate_address_state","cmp_enabled_state","snat_pool","enabled_state"]
        
        fields.each do |field|
          source_field = source_virtual_server.send(field)
          F5Utils.logger.debug("Setting target #{field} to '#{source_field}'")
          target_virtual_server.send("#{field}=",source_field)
        end

        F5Utils.logger.debug("Setting the rules and httpclass profiles")        

        target_virtual_server.httpclass_profiles = source_virtual_server.httpclass_profiles
        target_virtual_server.authentication_profiles = source_virtual_server.authentication_profiles
        target_virtual_server.rules = source_virtual_server.rules

      rescue => exception
        puts $!.inspect
        puts exception.backtrace

        target_virtual_server.destroy if target_virtual_server
        exit 1
      end

      F5Utils.logger.info("Copy of the virtual server done")        

    end
    
                                                                      
  # :name      => "The name of the virtual host"
  # :address   => "the ip address of the virtual server"
  # :port      => "the port the server is going to listen to"
  # :protocol  => "a protocol type"
  # :wildmask  => "The wildmask of the virtual server"
  # :type => "The type of the virtual_server"
  # :default_pool_name  => "The default pool name"
  # :profiles 

      
  end

  class ProfileHttpClass

    def self.list
      IControl::LocalLB::ProfileHttpClass.find(:all).sort{|a,b| a.id <=> b.id}.each { |i| puts i.id }
    end

    def self.rename(source,target)
      unless source_profile = IControl::LocalLB::ProfileHttpClass.find(source)
        puts "Error, no such profile (#{source})"
        exit 1
      end
      if IControl::LocalLB::ProfileHttpClass.find(target)
        puts "Error, target profile already exists"
        exit 1
      end
      unless target
        puts "Error, target not specified"
        exit 0
      end
            
      F5Utils.logger.info("Creating a new profile copy of the previous one")
      target_profile = IControl::LocalLB::ProfileHttpClass.create!(target)
      begin
        F5Utils.logger.info("Copying every field from the source to the target")
        if source_profile.pool
          F5Utils.logger.debug("Setting #{source_profile.pool.id} as target default pool")
          target_profile.pool = source_profile.pool
        else
          F5Utils.logger.debug("Not changing the pool as its empty")
        end
        if source_profile.default_profile
          F5Utils.logger.debug("Setting #{source_profile.default_profile.id} as target default profile")
          target_profile.default_profile = source_profile.default_profile
        else
          F5Utils.logger.debug("Not changing the default profile as its empty")
        end
        ["host","cookie","header","path"].each do |type|
          F5Utils.logger.info("Copying #{type} match patterns")
          source_profile.send("#{type}_match_pattern").each do |pattern|
            F5Utils.logger.debug("Adding #{pattern.inspect} to the target #{type}s match pattenrs")
            target_profile.send("add_#{type}_match_pattern",pattern)
          end
        end
        redirect = source_profile.redirect_location
        if redirect
          target_profile.set_redirect_location(redirect[:rule],redirect[:default_flag])
        end
        url = source_profile.rewrite_url
        if url
          target_profile.set_rewrite_url(url[:rule],url[:default_flag])
        end
        F5Utils.logger.info("Copy of the profile is done")
        
        F5Utils.logger.info "Checking dependencies (Virtual Servers)"
        
        virtual_servers = IControl::LocalLB::VirtualServer.find(:all)
        virtual_servers_affected = virtual_servers.select do |i|
          i.httpclass_profiles.to_a.map{|i| i.id}.include? source
        end
        F5Utils.logger.warn("Virtual Server affected [" + virtual_servers_affected.map{ |i| i.id }.join(",") + "]") if virtual_servers_affected.length > 0 
        
        virtual_servers_affected.each do |virtual_server|
          F5Utils.logger.info("Changing the profiles of the #{virtual_server.id} virtual_server")
          httpclass_profiles = virtual_server.httpclass_profiles
          httpclass_profiles.to_a.each_with_index {|element,i| httpclass_profiles[i] = target_profile if element.id == source_profile.id }
          httpclass_profiles.save!
        end
        F5Utils.logger.info "Checking whether there are profiles with this one as parent"
        httpclass_profiles = IControl::LocalLB::ProfileHttpClass.find(:all)
        httpclass_profiles.each do |httpclass_profile|
          if httpclass_profile.default_profile == source_profile
            F5Utils.logger.info "Found a profile that has #{source_profile.id} as default profile (#{httpclass_profile.id})"
            httpclass_profile.default_profile = target_profile
            F5Utils.logger.info "Changed"
          end
        end
        F5Utils.logger.info "Deleting the source profile"
        source_profile.delete_profile
        F5Utils.logger.info "Done"
      rescue
        F5Utils.logger.error "Error when trying to rename the profile"
        F5Utils.logger.error $!
        target_profile.delete_profile
      end
    end
  end

  class Pool

    def self.list
      pools = IControl::LocalLB::Pool.find(:all)
      pools.sort{|a,b| a.id <=> b.id}.each { |i| puts i.id }
    end
    
    def self.rename(source,target)
      unless source_pool = IControl::LocalLB::Pool.find(source)
        puts "Error, no such pool (#{source})"
        exit 0
      end
      if IControl::LocalLB::Pool.find(target)
        puts "Error, target pool already exists"
        exit 0
      end
      unless target
        puts "Error, target not specified"
        exit 0 
      end
      F5Utils.logger.debug("Checking dependencies")
      profiles = IControl::LocalLB::ProfileHttpClass.find(:all)      
      profiles_affected = profiles.select { |i| i.pool && i.pool.id == source_pool.id }   
      F5Utils.logger.warn("Dependencies found #{profiles_affected.map{|i| i.id}.inspect}") if profiles_affected.length >= 1
      
      F5Utils.logger.debug "Creating a new pool as a copy of the previous"
      new_pool = source_pool.clone(target)
      
      F5Utils.logger.debug "Rearranging the affected profile/s"
      profiles_affected.each do |profile|
        F5Utils.logger.debug "Changing the pool of #{profile.id}"
        profile.pool = new_pool
      end

      F5Utils.logger.debug "Checking dependencies (Virtual Servers)"
      virtual_servers = IControl::LocalLB::VirtualServer.find(:all)
      virtual_servers_affected = virtual_servers.select do |i| 
        default_pool =  i.default_pool
        if default_pool && default_pool.id
          default_pool.id == source_pool.id 
        else
          nil
        end
      end
      F5Utils.logger.debug "Rearranging the affected virtual servers"
      virtual_servers_affected.each do |virtual_server|
        F5Utils.logger.debug "Changing the pool of #{virtual_server.id}"
        virtual_server.default_pool = new_pool
      end

      F5Utils.logger.debug "Waiting for the new pool to be ready"
      count = 0
      while new_pool.object_status[:availability_status] != "AVAILABILITY_STATUS_GREEN"  && count < 5 do 
        puts new_pool.object_status.inspect
        sleep 1
        count +=1 
      end
      F5Utils.logger.warn "Pool availability check timeout, pool not available, checking whether the source is not available either" if count==5
      if new_pool.object_status[:availability_status]  == source_pool.object_status[:availability_status]          
        F5Utils.logger.debug "Deleting the previous pool"
        source_pool.destroy
      else
        F5Utils.logger.error "Not deleting cause the availability status differ"
      end
    end
  end
end

