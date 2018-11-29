class RegistrationsController < Milia::RegistrationsController

  def create

# have a working copy of the params in case Tenant callbacks

# make any changes

    tenant_params = sign_up_params_tenant

    user_params = sign_up_params_user

    coupon_params = sign_up_params_coupon

    sign_out_session!

# next two lines prep signup view parameters

    prep_signup_view( tenant_params, user_params, coupon_params )

# validate recaptcha first unless not enabled

    if !::Milia.use_recaptcha || verify_recaptcha

      Tenant.transaction do

        @tenant = Tenant.create_new_tenant( tenant_params, user_params, coupon_params)

        if @tenant.errors.empty? # tenant created

          if @tenant.plan == 'premium'

            @payment = Payment.new({ email: user_params["email"],

                                     token: params[:payment]["token"],

                                     tenant: @tenant })

            flash[:error] = "Please, check registration errors" unless @payment.valid?

            begin

              @payment.process_payment

              @payment.save

            rescue Exception => e

              flash[:error] = e.message

              @tenant.destroy

              log_action('Payment failed')

              render :new and return

            end

          end

        else

          resource.valid?

          log_action( "tenant create failed", @tenant )

          render :new and return

        end

        if flash[:error].blank? || flash[:error].empty? # payment successful

          initiate_tenant( @tenant ) # first time stuff for new tenant

          devise_create( user_params ) # devise resource(user) creation; sets resource

          if resource.errors.empty? # SUCCESS!

            log_action( "signup user/tenant success", resource )

# do any needed tenant initial setup

            Tenant.tenant_signup(resource, @tenant, coupon_params)

          else # user creation failed; force tenant rollback

            log_action( "signup user create failed", resource )

            raise ActiveRecord::Rollback # force the tenant transaction to be rolled back

          end # if..then..else for valid user creation

        else

          resource.valid?

          log_action( "Payment processing failed", @tenant )

          render :new and return

        end # if .. then .. else no tenant errors

      end # wrap tenant/user creation in a transaction

    else

      flash[:error] = "Recaptcha codes didn't match; please try again"

# all validation errors are passed when the sign_up form is re-rendered

      resource.valid?

      @tenant.valid?

      log_action( "recaptcha failed", resource )

      render :new and return

    end

  end
end