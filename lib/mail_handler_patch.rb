module RedmineHelpdesk
  module MailHandlerPatch
    def self.included(base) # :nodoc:
      base.send(:include, InstanceMethods)
      
      base.class_eval do
        alias_method_chain :dispatch_to_default, :helpdesk
        alias_method_chain :receive_issue_reply, :helpdesk
      end
    end
    
    module InstanceMethods
      private
      # Overrides the dispatch_to_default method to
      # set the owner-email of a new issue created by
      # an email request
      def dispatch_to_default_with_helpdesk
        issue = receive_issue
        roles = issue.author.roles_for_project(issue.project)
        # add owner-email only if the author has assigned some role with
        # permission treat_user_as_supportclient enabled
        if roles.any? {|role| role.allowed_to?(:treat_user_as_supportclient) }
          sender_email = @email.from.first
          # turn off the block and use the subroutine instead
          if false
          email_details = "From: " + @email[:from].formatted.first + "\n"
          email_details << "To: " + @email[:to].formatted.join(', ') + "\n"
          if !@email.cc.nil?
            email_details << "Cc: " + @email[:cc].formatted.join(', ') + "\n"
          end
          email_details << "Date: " + @email[:date].to_s + "\n"
          email_details << "Subject: " + @email[:subject].to_s + "\n"
          email_details = "<pre>\n" + Mail::Encodings.unquote_and_convert_to(email_details, 'utf-8') + "</pre>"
	  end
	  email_details = compose_email_details()
          issue.description = email_details + issue.description
          issue.save
          custom_field = CustomField.find_by_name('owner-email')
          custom_value = CustomValue.find(
            :first,
            :conditions => ["customized_id = ? AND custom_field_id = ?", issue.id, custom_field.id]
          )
          custom_value.value = sender_email
          custom_value.save(:validate => false) # skip validation!
          # regular email sending to known users is done
          # on the first issue.save. So we need to send
          # the notification email to the supportclient
          # on our own.
          HelpdeskMailer.email_to_supportclient(issue, sender_email).deliver
        end
        after_dispatch_to_default_hook issue
        return issue
      end
      
      # let other plugins the chance to override this
      # method to hook into dispatch_to_default
      def after_dispatch_to_default_hook(issue)
      end
      
      # Fix an issue with email.has_attachments?
      def add_attachments(obj)
         if !email.attachments.nil? && email.attachments.size > 0
           email.attachments.each do |attachment|
             obj.attachments << Attachment.create(:container => obj,
                               :file => attachment.decoded,
                               :filename => attachment.filename,
                               :author => user,
                               :content_type => attachment.mime_type)
          end
        end
      end
      # just copy and paste the lines above
      def compose_email_details()
	  email_details = "From: " + @email[:from].formatted.first + "\n"
          email_details << "To: " + @email[:to].formatted.join(', ') + "\n"
          if !@email.cc.nil?
            email_details << "Cc: " + @email[:cc].formatted.join(', ') + "\n"
          end
          email_details << "Date: " + @email[:date].to_s + "\n"
          email_details << "Subject: " + @email[:subject].to_s + "\n"
          email_details = "<pre>\n" + Mail::Encodings.unquote_and_convert_to(email_details, 'utf-8') + "</pre>"
          email_details
      end
      # Overrides the receive_issue_reply method to
      # append email details
      def receive_issue_reply_with_helpdesk(issue_id, from_journal=nil)
        journal = receive_issue_reply_without_helpdesk(issue_id, from_journal)
        email_details = compose_email_details()
        journal.notes = email_details + journal.notes
        journal.save
        journal
      end
      
    end # module InstanceMethods
  end # module MailHandlerPatch
end # module RedmineHelpdesk

# Add module to MailHandler class
MailHandler.send(:include, RedmineHelpdesk::MailHandlerPatch)
