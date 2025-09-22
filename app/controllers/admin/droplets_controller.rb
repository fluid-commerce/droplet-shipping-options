class Admin::DropletsController < AdminController
  def create
    result = DropletUseCase::Create.call

    if result[:success]
      redirect_to admin_dashboard_path, notice: "Droplet created successfully"
    else
      redirect_to admin_dashboard_path, alert: "Failed to create droplet: #{result[:error]}"
    end
  end

  def update
    result = DropletUseCase::Update.call

    if result[:success]
      redirect_to admin_dashboard_path, notice: "Droplet updated successfully"
    else
      redirect_to admin_dashboard_path, alert: "Failed to update droplet: #{result[:error]}"
    end
  end
end
