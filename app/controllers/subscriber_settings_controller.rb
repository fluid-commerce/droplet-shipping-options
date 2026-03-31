# frozen_string_literal: true

class SubscriberSettingsController < ApplicationController
  include DriAuthentication

  def edit; end

  def update
    @company.assign_attributes(settings_params)

    if @company.save
      redirect_to edit_subscriber_setting_path(dri: params[:dri]),
                  notice: "Subscriber settings updated successfully"
    else
      flash.now[:alert] = "Failed to update settings: #{@company.errors.full_messages.join(', ')}"
      render :edit
    end
  end

private

  def settings_params
    {
      settings: {
        free_shipping_for_subscribers: params.dig(:company, :free_shipping_for_subscribers) == "1",
      },
    }
  end
end
