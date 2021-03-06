module Misfit

  module PaymentValidators
    # ALL payment validations go in here so that they are available to the loan product
    def amount_must_be_paid_in_full_or_not_at_all
      case type
        when :principal
          if amount < loan.scheduled_principal_due_on(received_on) and amount != 0
            return [false, "amount must be paid in full or not at all"]
          else
            return true
          end
        when :interest
          if amount < loan.scheduled_interest_due_on(received_on) and amount != 0
            return [false, "amount must be paid in full or not at all"]
          else
            return true
          end
        else
          return true
      end
    end

    def fees_applicable_to_loan_paid_before_first_payment?
      if self.loan and (type==:principal or type==:interest) and loan.payments(:type => [:principal, :interest]).count==0
        if not loan.fees_paid?
          return [false, "All fees applicable to this loan are not paid yet"] 
        end
      end
      return true
    end

    def fees_applicable_to_client_paid_before_first_payment?
      if self.loan and (type==:principal or type==:interest) and loan.payments(:type => [:principal, :interest]).count==0
        if not loan.client.fees_paid?
          return [false, "All fees applicable to this client are not paid yet"]
        end
      end
      return true
    end

    def not_paying_too_much_p_and_i?
      if new?  # do not do this check on updates, it will count itself double
        if type == :principal
          a = loan.actual_outstanding_principal_on(received_on)
        elsif type == :interest
          a = loan.actual_outstanding_interest_on(received_on)
        end
        if (not a.blank?) and amount - a > 0.01
          return [false, "#{type} is more than the total #{type} due"]
        end
      end
      true
    end

    def not_paying_too_much?
      if new?  # do not do this check on updates, it will count itself double
        if type == :principal
          a = loan.actual_outstanding_principal_on(received_on)
        elsif type == :interest
          a = loan.actual_outstanding_interest_on(received_on)
        elsif type == :fees
          loan_fees = loan.total_fees_payable_on(received_on) if loan
          loan_fees_amount = loan_fees ? loan_fees : 0
          client_fees = client.total_fees_payable_on(received_on) if client and not loan
          client_fees_amount = client_fees ? client_fees : 0
          a = loan_fees_amount + client_fees_amount
        end      
        if (not a.blank?) and amount - a > 0.01
          return [false, "#{type} is more than the total #{type} due"]
        end
      end
      true
    end
    def not_paying_too_much_in_total?
      if new?   # do not do this check on updates, it will count itself double
        a = loan.actual_outstanding_total_on(received_on)
        if total > a
          return [false, "Total is more than the loans outstanding total"]
        end
      end
      true
    end



  end    #PaymentValidators

  module LoanValidators
    def installments_are_integers?
      return [false, "Number of installments not defined"] if number_of_installments.nil? or number_of_installments.blank?
      return [false, "Amount not defined"] unless amount
      return [false, "Interest rate not defined"] unless interest_rate
      return [false, "Installment frequency is not defined"] unless installment_frequency
      return [false, "Scheduled first payment date is not defined"] unless scheduled_first_payment_date

      self.payment_schedule.each do |date, val|
        pri = val[:principal]
        int = val[:interest]
        return [false, "Amount must yield integer installments"] if ((pri+int) - (pri+int).to_i).abs > 0.01
      end
      return true
    end
    
    def part_of_a_group_and_passed_grt?
      return [false, "Client is not part of a group"] if not client or client.client_group_id.nil? or client.client_group_id.blank?
      return [false, "Client has not passed GRT"] if client.grt_pass_date.nil? or client.grt_pass_date.blank?
      return true
    end

    def scheduled_dates_must_be_center_meeting_days #this function is only for repayment dates
      return [false, "Not client defined"] unless client
      center = client.center
      failed = []
      correct_weekday = nil 
      ["scheduled_first_payment_date"].each do |d|
        # if the loan disbursal date is set and it is not being set right now, no need to check as the loan has been already disbursed
	# hence we need not check it again
	if self.disbursal_date and not self.dirty_attributes.keys.find{|da| da.name == :disbursal_date} 
	  return true
	end
	  
	if date = instance_eval(d) and not date.weekday == center.meeting_day_for(date).to_sym
          failed << d.humanize
          correct_weekday = center.meeting_day_for(date)
        end
      end
      
      return [false, "#{failed.join(",")} must be #{correct_weekday}"]      unless failed.blank?
      return true
    end

    def disbursal_dates_must_be_center_meeting_days #this function is only for disbursal dates
      return [false, "Not client defined"] if not client
      center = client.center
      failed = []
      correct_weekday = nil 
      ["scheduled_disbursal_date", "disbursal_date"].each do |d|
	# if the loan disbursal date is set and it is not being set right now, no need to check as the loan has been already disbursed
	next unless instance_eval(d)
	return true if self.disbursal_date and not self.dirty_attributes.keys.find{|da| da.name == :disbursal_date}
	if not date = instance_eval(d) or not date.weekday == center.meeting_day_for(date)
          failed << d.humanize
          correct_weekday = center.meeting_day_for(date)
        end
      end
      return [false, "#{failed.join(",")} must be #{correct_weekday}"]      unless failed.blank?
      return true
    end

    def insurance_must_be_mandatory
      return [false, "Client does not have an insurance"] if client.insurance_policies.nil? or client.insurance_policies.length==0
      return [false, "Insurance is not valid anymore"]    if client.insurance_policies.sort_by{|x| x.date_to}.last.date_to <= self.applied_on
      return [false, "Insurance is not active"]           if not client.insurance_policies.collect{|x| x.status}.include?(:active)
      return true
    end

    def client_fee_should_be_paid
      if self.new? and not client.fees_paid?
        return [false, "All fees applicable to this client are not paid yet"]
      end
      return true
    end
    
    def loans_must_not_be_duplicated
      if self.new? and Loan.first(:client_id => self.client_id, :applied_on => self.applied_on, :amount => self.amount)
	return [false, "The Loan seems to be a duplicate entry"]
      else
	return true
      end
    end
    
    def check_payment_of_fees_before_disbursal
      if self.approved_on and not self.new? 
        if not self.fees_paid?
          return [false, "All fees applicable to this loan are not paid yet"] 
        else
          return true
        end
      else
        return true
      end
    end

    def prepayment_must_be_per_system_numbers
      return true
    end

    def only_one_loan_per_client
      #this validation is to check that a particular client is given only one active loan at a time.
      lp_ids     = LoanProduct.all(:loan_validation_methods.like => "%only_one_loan%").aggregate(:id)
      lh_statuses  = LoanHistory.latest(:client_id => @client.id, :loan_product_id => lp_ids).map{|x| x.status} # using map because aggregate returns nil! bug?
      outstanding_statuses = [:applied_in_future, :applied, :approved, :disbursed, :outstanding]
      return [false, "Cannot create loan as client: #{@client.name} (id: #{@client.id}) already has an active loan"] if outstanding_statuses.map{|s| lh_statuses.include?(s)}.include?(true)
      return true
    end

  end    #LoanValidators 
end
