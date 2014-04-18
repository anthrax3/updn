class UsersController < ApplicationController
  before_filter :require_logged_in_user, :only => [:has_funds?]

  def show
    @showing_user = User.where(:username => params[:username]).first!
    @title = "User #{@showing_user.username}"
  end

  def tree
    @title = "Users"

    users = User.order("id DESC").to_a

    @user_count = users.length
    @users_by_parent = users.group_by(&:invited_by_user_id)
  end

  def invite
    @title = "Pass Along an Invitation"
  end  
  
  def has_funds? 
    check = @user.check_balance 0.01 
    unless @user.is_admin? || check[0] 
      return render text: to_8f(check[1]), status: 400
    end

    render text: 'ok'
  end
end
