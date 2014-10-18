class Admin::AdminController < ApplicationController
  before_filter :auth
  
  def auth
    if request.remote_host != 'localhost'
      redirect_to '/404.html', :status => 404
    end
  end
end
